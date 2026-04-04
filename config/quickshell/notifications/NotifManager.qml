import Quickshell
import Quickshell.Services.Notifications
import QtQuick

Scope {
    id: root

    property bool dnd: false
    property list<Notification> notifications: []

    // Popup queue: newest first, max 5 shown
    property list<Notification> popupQueue: []

    NotificationServer {
        id: server
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        keepOnReload: true

        onNotification: notif => {
            notif.tracked = true;
            root.notifications = [notif, ...root.notifications];

            if (!root.dnd) {
                root.popupQueue = [notif, ...root.popupQueue].slice(0, 5);

                // Auto-expire popup after timeout or 5s default
                const timeout = notif.expireTimeout > 0 ? notif.expireTimeout * 1000 : 5000;
                Qt.callLater(() => {
                    popupTimer.createObject(root, { notification: notif, interval: timeout });
                });
            }
        }
    }

    property Component popupTimer: Timer {
        required property Notification notification
        running: true
        onTriggered: {
            root.removeFromPopup(notification);
            this.destroy();
        }
    }

    function removeFromPopup(notif) {
        popupQueue = popupQueue.filter(n => n !== notif);
    }

    function dismiss(notif) {
        notif.dismiss();
        notifications = notifications.filter(n => n !== notif);
        removeFromPopup(notif);
    }

    function dismissAll() {
        for (const n of notifications) n.dismiss();
        notifications = [];
        popupQueue = [];
    }
}
