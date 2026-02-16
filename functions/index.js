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