/* Shown while the install runs. */
import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#141414"
        }
        Image {
            anchors.fill: parent
            source: "welcome.png"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.55
        }
        Text {
            anchors.centerIn: parent
            text: "Installing ChiropteraOS"
            color: "#FFFFFF"
            font.pixelSize: 28
        }
        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            anchors.horizontalCenter: parent.horizontalCenter
            text: "The last step moves the system to CachyOS and can take a while."
            color: "#E6E6E6"
            font.pixelSize: 15
        }
    }

    function onActivate() { }
    function onLeave() { }
}
