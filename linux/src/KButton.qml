import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material

// Material buttons are fully rounded unless told otherwise; Kalam's follow
// the window corners like everything else.
Button {
    Material.roundedScale: theme.radius
}
