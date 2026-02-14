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

    return date.toLocaleString('en-US', options);
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
                promises.push(sendReminderNotification(db, doc.id, reminder, false));
            }
        });

        // Check snoozed reminders
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

        // For snoozed reminders, use the ORIGINAL time for display
        const displayTime = isSnoozed && reminder.originalTime
            ? reminder.originalTime
            : reminder.time;

        const timeStr = formatTime(displayTime);
        const description = reminder.description || '';
        const formattedBody = `Scheduled for ${timeStr}:\n${description}`;

        // For snoozed reminders, use the ORIGINAL reminder ID
        const reminderIdToUse = isSnoozed && reminder.originalReminderId
            ? reminder.originalReminderId
            : docId;

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
                time: timeStr
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
            // Delete snoozed reminder after sending (it's temporary)
            await db.collection('snoozed_reminders').doc(docId).delete();
            console.log(`Deleted snoozed reminder ${docId}`);
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