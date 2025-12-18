/*
    SPDX-FileCopyrightText: 2016 David Edmundson <davidedmundson@kde.org>
    SPDX-FileCopyrightText: 2022 Aleix Pol Gonzalez <aleixpol@kde.org>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

import QtQuick 2.15

import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.kirigami 2.20 as Kirigami

PlasmaComponents.ToolButton {
    id: root

    property int currentIndex: -1
    property string currentUser: ""
    property bool sessionInitialized: false

    // Find session index by name (searches for partial match)
    function findSessionIndex(sessionName) {
        for (var i = 0; i < sessionModel.rowCount(); i++) {
            var item = instantiator.objectAt(i)
            if (item && item.text && item.text.toLowerCase().indexOf(sessionName.toLowerCase()) !== -1) {
                return i
            }
        }
        return -1
    }

    // Get default session for a user, returns -1 if no preference
    function getDefaultSessionForUser(user) {
        switch (user.toLowerCase()) {
            case "dreamingcodes":
                return findSessionIndex("hyprland")
            case "riccardo":
                return findSessionIndex("plasma")
            default:
                return -1
        }
    }

    // Update session based on user, with fallback to global lastIndex
    function updateSessionForUser() {
        // Wait until instantiator has created all items
        if (instantiator.count < sessionModel.rowCount()) {
            return
        }
        
        var userDefault = getDefaultSessionForUser(currentUser)
        if (userDefault !== -1) {
            currentIndex = userDefault
        } else if (currentIndex < 0) {
            currentIndex = sessionModel.lastIndex
        }
        sessionInitialized = true
    }

    text: i18nd("plasma-desktop-sddm-theme", "Desktop Session: %1", instantiator.objectAt(currentIndex)?.text ?? "")
    visible: menu.count > 1

    Component.onCompleted: {
        // Initial fallback, will be updated when instantiator is ready
        if (currentIndex < 0) {
            currentIndex = sessionModel.lastIndex
        }
    }

    onCurrentUserChanged: {
        updateSessionForUser()
    }

    checkable: true
    checked: menu.opened
    onToggled: {
        if (checked) {
            menu.popup(root, 0, 0)
        } else {
            menu.dismiss()
        }
    }

    signal sessionChanged()

    PlasmaComponents.Menu {
        Kirigami.Theme.colorSet: Kirigami.Theme.Window
        Kirigami.Theme.inherit: false

        id: menu
        Instantiator {
            id: instantiator
            model: sessionModel
            onObjectAdded: (index, object) => {
                menu.insertItem(index, object)
                // Try to update session when items are added
                root.updateSessionForUser()
            }
            onObjectRemoved: (index, object) => menu.removeItem(object)
            delegate: PlasmaComponents.MenuItem {
                text: model.name
                onTriggered: {
                    root.currentIndex = model.index
                    sessionChanged()
                }
            }
        }
    }
}
