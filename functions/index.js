const {onSchedule} = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');
admin.initializeApp();

// Helper function to format time
function formatTime(timestamp) {
    const date = timestamp.toDate();
    let hours = date.getHours();
    const minutes = date.getMinutes();
    const ampm = hours >= 12 ? 'PM' : 'AM';

    hours = hours % 12;
    hours = hours ? hours : 12; // 0 should be 12
    const minutesStr = minutes < 10 ? '0' + minutes : minutes;

    return `${hours}:${minutesStr} ${ampm}`;
}

// This function runs every 1 minute to check for due reminders
exports.sendScheduledReminders = onSchedule('every 1 minutes', async (event) => {
    const db = admin.firestore();
    const now = admin.firestore.Timestamp.now();

    try {
        // Get all reminders that are due and not yet completed
        const remindersSnapshot = await db.collection('reminders')
            .where('time', '<=', now)
            .where('completed', '==', false)
            .get();

        if (remindersSnapshot.empty) {
            console.log('No reminders to send');
            return null;
        }

        const promises = [];

        remindersSnapshot.forEach(doc => {
            const reminder = doc.data();

            // Format time and body
            const timeStr = formatTime(reminder.time);
            const description = reminder.description || '';
            const formattedBody = `Scheduled for ${timeStr}:\n${description}`;

            // Get patient's FCM token and send notification
            const sendNotification = db.collection('users')
                .doc(reminder.patientId)
                .get()
                .then(userDoc => {
                    if (!userDoc.exists) {
                        console.log(`User ${reminder.patientId} not found`);
                        return null;
                    }

                    const token = userDoc.data().fcmToken;

                    if (!token) {
                        console.log(`No FCM token for user ${reminder.patientId}`);
                        return null;
                    }

                    // Send the notification with reminder data
                    return admin.messaging().send({
                        token: token,
                        notification: {
                            title: `Reminder: ${reminder.title || 'Task'}`,
                            body: formattedBody
                        },
                        data: {
                            reminderId: doc.id,
                            title: reminder.title || '',
                            description: reminder.description || '',
                            timestamp: reminder.time.toMillis().toString(),
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
                })
                .then(() => {
                    // Mark reminder as completed
                    return doc.ref.update({ completed: true });
                })
                .catch(error => {
                    console.error(`Error sending reminder ${doc.id}:`, error);
                });

            promises.push(sendNotification);
        });

        await Promise.all(promises);
        console.log(`Sent ${promises.length} reminders`);
        return null;

    } catch (error) {
        console.error('Error in sendScheduledReminders:', error);
        return null;
    }
});