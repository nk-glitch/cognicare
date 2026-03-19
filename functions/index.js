const {onSchedule} = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
admin.initializeApp();

// Helper function to format time in Eastern Time
function formatTime(timestamp) {
    const date = timestamp.toDate();

    // Format in Eastern Time (America/New_York)
    const options = {
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        timeZone: 'America/New_York'
    };

    // Use Intl.DateTimeFormat for reliable timezone conversion
    const formatter = new Intl.DateTimeFormat('en-US', options);
    return formatter.format(date);
}

// This function runs every 1 minute to check for due reminders
exports.sendScheduledReminders = onSchedule('every 1 minutes', async (event) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    try {
        const promises = [];

        // Check regular reminders that haven't been sent yet
        const remindersSnapshot = await db.collection('reminders')
            .where('time', '<=', now)
            .where('completed', '==', false)
            .get();

        // Filter out reminders that already had notifications sent
        remindersSnapshot.forEach(doc => {
            const reminder = doc.data();
            // Only send if notification hasn't been sent yet
            if (!reminder.notificationSent) {
                const isSnoozed = reminder.isSnoozed === true;
                promises.push(sendReminderNotification(db, doc.id, reminder, isSnoozed));
            }
        });

        // Check snoozed reminders (old collection - for backwards compatibility)
        const snoozedSnapshot = await db.collection('snoozed_reminders')
            .where('time', '<=', now)
            .where('completed', '==', false)
            .get();

        snoozedSnapshot.forEach(doc => {
            const reminder = doc.data();
            promises.push(sendReminderNotification(db, doc.id, reminder, true));
        });

        if (promises.length === 0) {
            console.log('No reminders to send');
            return null;
        }

        await Promise.all(promises);
        console.log(`Sent ${promises.length} reminders`);
        return null;

    } catch (error) {
        console.error('Error in sendScheduledReminders:', error);
        return null;
    }
});

async function sendReminderNotification(db, docId, reminder, isSnoozed) {
    try {
        // Get patient's FCM token
        const userDoc = await db.collection('users')
            .doc(reminder.patientId)
            .get();

        if (!userDoc.exists) {
            console.log(`User ${reminder.patientId} not found`);
            return null;
        }

        const token = userDoc.data().fcmToken;

        if (!token) {
            console.log(`No FCM token for user ${reminder.patientId}`);
            return null;
        }

        // For snoozed reminders, use the stored originalTimeText if available
        // This avoids timezone conversion issues since it's pre-formatted
        let timeStr;
        if (isSnoozed && reminder.originalTimeText) {
            // Use the pre-formatted time string from Flutter app
            timeStr = reminder.originalTimeText;
        } else if (isSnoozed && reminder.originalTime) {
            // Fallback: format the original time if originalTimeText not available
            timeStr = formatTime(reminder.originalTime);
        } else {
            // For regular reminders, format the time
            timeStr = formatTime(reminder.time);
        }

        const description = reminder.description || '';
        const snoozeSuffix = isSnoozed ? ' (Snoozed)' : '';
        const formattedBody = `Scheduled for ${timeStr}${snoozeSuffix}${description ? ':\n' + description : ''}`;

        // For snoozed reminders, use the ORIGINAL reminder ID if available
        const reminderIdToUse = isSnoozed && reminder.originalReminderId
            ? reminder.originalReminderId
            : docId;

        // Determine which timestamp to use for the data payload
        const displayTime = isSnoozed && reminder.originalTime
            ? reminder.originalTime
            : reminder.time;

        // Send the notification
        await admin.messaging().send({
            token: token,
            notification: {
                title: `Reminder: ${reminder.title || 'Task'}`,
                body: formattedBody
            },
            data: {
                reminderId: reminderIdToUse,
                title: reminder.title || '',
                description: reminder.description || '',
                timestamp: displayTime.toMillis().toString(),
                time: timeStr,
                isSnooze: isSnoozed ? 'true' : 'false',
                originalBodyText: isSnoozed && reminder.originalTimeText
                    ? `Scheduled for ${reminder.originalTimeText}${description ? ':\n' + description : ''}`
                    : ''
            },
            android: {
                priority: 'high',
                notification: {
                    channelId: 'reminder_channel',
                    sound: 'default'
                }
            }
        });

        // Handle post-notification cleanup
        if (isSnoozed) {
            // Check if this is from the old snoozed_reminders collection
            const snoozedDoc = await db.collection('snoozed_reminders').doc(docId).get();
            if (snoozedDoc.exists) {
                // Delete snoozed reminder after sending (it's temporary)
                await db.collection('snoozed_reminders').doc(docId).delete();
                console.log(`Deleted snoozed reminder from old collection ${docId}`);
            } else {
                // It's in the regular reminders collection
                await db.collection('reminders').doc(docId).update({
                    notificationSent: true
                });
                console.log(`Marked snoozed reminder ${docId} as sent`);
            }
        } else {
            // For regular reminders, add a 'notificationSent' flag to prevent duplicate sends
            // but DON'T mark as completed - let the user do that
            await db.collection('reminders').doc(docId).update({
                notificationSent: true
            });
            console.log(`Marked notification sent for reminder ${docId}`);
        }

        return null;

    } catch (error) {
        console.error(`Error sending reminder ${docId}:`, error);
        return null;
    }
}
// ─── Missed Reminder Alert System ────────────────────────────────────────────
// Runs every minute. If a reminder was due 5+ minutes ago and the patient
// hasn't marked it complete, write a caretaker_alerts doc and send a push
// notification to every accepted caretaker for that patient.

exports.checkMissedReminders = onSchedule('every 1 minutes', async (event) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    // Query all overdue, incomplete, unalerted reminders (up to 24h ago to be safe)
    const twentyFourHoursAgo = admin.firestore.Timestamp.fromMillis(now.toMillis() - 24 * 60 * 60 * 1000);

    try {
        const missedSnapshot = await db.collection('reminders')
            .where('time', '<=', now)
            .where('time', '>=', twentyFourHoursAgo)
            .where('completed', '==', false)
            .get();

        if (missedSnapshot.empty) return null;

        const promises = [];
        missedSnapshot.forEach(doc => {
            const reminder = doc.data();

            // Skip if alert already sent
            if (reminder.caretakerAlertSent) return;

            // Skip if caretaker alerts are disabled for this reminder
            const delayMinutes = reminder.missedAlertDelayMinutes;
            if (delayMinutes === null || delayMinutes === undefined) return;

            // Check if enough time has passed since the reminder was due
            const dueMillis = reminder.time.toMillis();
            const elapsedMinutes = (now.toMillis() - dueMillis) / 60000;
            if (elapsedMinutes < delayMinutes) return;

            promises.push(alertCaretakers(db, doc.id, reminder));
        });

        if (promises.length > 0) {
            await Promise.all(promises);
            console.log(`Sent ${promises.length} missed reminder alerts`);
        }

        return null;
    } catch (error) {
        console.error('Error in checkMissedReminders:', error);
        return null;
    }
});

async function alertCaretakers(db, reminderId, reminder) {
    try {
        const patientId = reminder.patientId;
        if (!patientId) return;

        // Find all accepted caretakers for this patient
        const relationshipsSnapshot = await db
            .collection('patient_caretaker_relationships')
            .where('patientId', '==', patientId)
            .where('status', '==', 'accepted')
            .get();

        // Mark as sent immediately so we don't retry even if no caretakers
        await db.collection('reminders').doc(reminderId).update({ caretakerAlertSent: true });

        if (relationshipsSnapshot.empty) return;

        const reminderTitle = reminder.title || 'Reminder';
        const timeStr = formatTime(reminder.time);
        const alertMessage = `A patient missed "${reminderTitle}" scheduled for ${timeStr}`;

        for (const relDoc of relationshipsSnapshot.docs) {
            const caretakerId = relDoc.data().caretakerId;
            if (!caretakerId) continue;

            // Write alert document (shows up in InboxPage)
            const alertRef = db.collection('caretaker_alerts').doc();
            await alertRef.set({
                caretakerId: caretakerId,
                patientId: patientId,
                reminderId: reminderId,
                message: alertMessage,
                createdAt: admin.firestore.FieldValue.serverTimestamp(),
                isRead: false,
            });

            // Push notification to caretaker
            const caretakerDoc = await db.collection('users').doc(caretakerId).get();
            if (!caretakerDoc.exists) continue;
            const token = caretakerDoc.data().fcmToken;
            if (!token) continue;

            await admin.messaging().send({
                token: token,
                notification: {
                    title: 'Missed Reminder Alert',
                    body: alertMessage,
                },
                data: {
                    type: 'caretaker_alert',
                    reminderId: reminderId,
                    patientId: patientId,
                    reminderTitle: reminderTitle,
                    alertMessage: alertMessage,
                },
                android: {
                    priority: 'high',
                    notification: {
                        channelId: 'reminder_channel',
                        sound: 'default',
                    },
                },
            }).catch(err => console.error(`FCM failed for caretaker ${caretakerId}:`, err));
        }

        console.log(`Alerted caretakers for missed reminder ${reminderId}`);
    } catch (error) {
        console.error(`Error alerting caretakers for reminder ${reminderId}:`, error);
    }
}
// ─── Geofence Breach Alert ────────────────────────────────────────────────────
// Triggers whenever a patient's location is written to Firestore.
// If the patient just crossed from inside → outside their safe zone,
// sends a push notification to the caretaker and logs to caretaker_alerts.

const { onDocumentWritten } = require('firebase-functions/v2/firestore');

function haversineDistance(lat1, lng1, lat2, lng2) {
    const R = 6371000;
    const toRad = (deg) => (deg * Math.PI) / 180;
    const dLat = toRad(lat2 - lat1);
    const dLng = toRad(lng2 - lng1);
    const a =
        Math.sin(dLat / 2) ** 2 +
        Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
    return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function formatDistance(metres) {
    if (metres >= 1000) return `${(metres / 1000).toFixed(1)} km`;
    return `${Math.round(metres)} m`;
}

exports.checkGeofence = onDocumentWritten(
    'patient_locations/{patientId}',
    async (event) => {
        const db = admin.firestore();
        const { patientId } = event.params;

        const newData = event.data?.after?.data();
        if (!newData) return;

        const { latitude, longitude } = newData;

        // Load geofence
        const geofenceSnap = await db.collection('geofences').doc(patientId).get();
        if (!geofenceSnap.exists) return;
        const geofence = geofenceSnap.data();
        if (!geofence.isActive) return;

        // Calculate distance
        const distance = haversineDistance(
            latitude, longitude,
            geofence.centerLat, geofence.centerLng,
        );
        const isOutside = distance > geofence.radiusMeters;

        // Read previous breach state — only alert on inside → outside transition
        const stateRef = db.collection('geofence_states').doc(patientId);
        const stateSnap = await stateRef.get();
        const wasOutside = stateSnap.exists ? (stateSnap.data().isOutside ?? false) : false;

        await stateRef.set(
            { isOutside, lastDistance: Math.round(distance), updatedAt: admin.firestore.FieldValue.serverTimestamp() },
            { merge: true },
        );

        if (!isOutside || wasOutside) return;

        // Get caretaker FCM token
        const caretakerSnap = await db.collection('users').doc(geofence.caretakerId).get();
        if (!caretakerSnap.exists) return;
        const fcmToken = caretakerSnap.data()?.fcmToken;
        if (!fcmToken) return;

        // Get patient name
        const patientSnap = await db.collection('users').doc(patientId).get();
        const patientData = patientSnap.data() || {};
        const patientName =
            `${patientData.firstName || ''} ${patientData.lastName || ''}`.trim() || 'Your patient';

        const distStr = formatDistance(distance);

        // Send FCM push
        await admin.messaging().send({
            token: fcmToken,
            notification: {
                title: '⚠️ Safe zone alert',
                body: `${patientName} has left "${geofence.label}" (${distStr} away)`,
            },
            data: {
                type: 'geofence_alert',
                patientId,
                patientName,
                distance: String(Math.round(distance)),
                geofenceLabel: geofence.label,
                caretakerId: geofence.caretakerId,
            },
            android: {
                priority: 'high',
                notification: { channelId: 'geofence_channel', color: '#F57C00' },
            },
            apns: { payload: { aps: { sound: 'default', badge: 1 } } },
        }).catch(err => console.error(`[geofence] FCM failed: ${err}`));

        // Log to caretaker_alerts (shows in inbox)
        await db.collection('caretaker_alerts').add({
            caretakerId: geofence.caretakerId,
            patientId,
            patientName,
            type: 'geofence_breach',
            geofenceLabel: geofence.label,
            distance: Math.round(distance),
            latitude,
            longitude,
            isRead: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`[geofence] Breach alert sent for ${patientId} (${distStr} from "${geofence.label}")`);
    }
);