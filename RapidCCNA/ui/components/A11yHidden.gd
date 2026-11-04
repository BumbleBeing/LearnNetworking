extends Control
## Hides a purely decorative control from screen readers. It still shows on screen.
## Attach with UI.hide_from_screen_readers(); only for nodes that have no script of their own.

func _notification(what: int) -> void:
	if what == NOTIFICATION_ACCESSIBILITY_UPDATE:
		AccessibilityServer.update_set_flag(get_accessibility_element(), AccessibilityServer.FLAG_HIDDEN, true)
