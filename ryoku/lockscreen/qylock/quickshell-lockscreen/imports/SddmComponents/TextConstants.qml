import QtQuick
import Ryoku.Ui.Singletons

QtObject {
    readonly property string welcomeText: I18n.tr("Welcome")
    readonly property string loginFailedText: I18n.tr("Login Failed")
    readonly property string loginSucceeded: I18n.tr("Welcome back!")
    readonly property string loginFailed: I18n.tr("Try again")
}
