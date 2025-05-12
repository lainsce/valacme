/* ui_helper.vala
 * UI helper functions
 */

/* Delegate for dirty state changes */
public delegate void DirtyChangedCallback(bool is_dirty);

/* Delegate for simple callback with no parameters */
public delegate void SimpleCallback();

/* UI helper class provides common UI creation methods */
public class AcmeUIHelper : Object {
    /* Create a command label with proper styling and click handler */
    public static Gtk.Label create_command_label(string command, owned SimpleCallback callback) {
        var label = new Gtk.Label(command);
        label.add_css_class("acme-command-label");
        
        var click = new Gtk.GestureClick();
        click.pressed.connect((n_press, x, y) => {
            callback();
        });
        label.add_controller(click);
        
        return label;
    }
    
    /* Create a dirty indicator drawing area with a reference to the dirty state */
    public static Gtk.DrawingArea create_dirty_indicator(bool initial_dirty_state, bool is_column = false) {
        var indicator = new Gtk.DrawingArea();
        indicator.set_size_request(12, 16);
        
        // Store dirty state and type in widget data
        indicator.set_data("dirty_state", initial_dirty_state);
        indicator.set_data("is_column", is_column);
        
        indicator.set_draw_func((drawing_area, context, width, height) => {
            // Get current dirty state from widget data
            bool is_dirty = drawing_area.get_data<bool>("dirty_state");
            bool is_column_box = drawing_area.get_data<bool>("is_column");
            
            // Set antialias to NONE for 1px lines
            context.set_antialias(Cairo.Antialias.NONE);
            
            // Draw border
            Gdk.RGBA border = {};
            border.parse("#8888cc");
            context.set_source_rgb(border.red, border.green, border.blue); // Cyan border
            context.set_line_width(2.0);
            context.rectangle(1.0, 1.0, width - 2.0, height - 2.0);
            context.stroke();
            
            // For columns, always fill with border color
            // For windows, only fill if dirty
            if (is_column_box || is_dirty) {
                Gdk.RGBA fill = {};
                fill.parse("#8888cc"); // Use same color as border for columns
                
                if (!is_column_box && is_dirty) {
                    // For dirty windows, use a darker blue
                    fill.parse("#000099");
                }

                context.set_source_rgb(fill.red, fill.green, fill.blue);
                context.rectangle(1.0, 1.0, width - 3.0, height - 3.0);
                context.fill();

            }
        });

        return indicator;
    }
    
    /* Set up standard keyboard shortcuts for text entry */
    public static void setup_text_keymap(Gtk.Entry entry, owned SimpleCallback on_enter) {
        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect((controller, keyval, keycode, state) => {
            // Check if Enter/Return was pressed
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                on_enter();
                return true; // Stop event propagation
            }
            return false; // Continue event propagation
        });
        entry.add_controller(key_controller);
    }

    /* Create scrolled window for text view with left-side scrollbar */
    public static Gtk.ScrolledWindow create_text_scrolled_window(Gtk.TextView text_view) {
        var scrolled = new Gtk.ScrolledWindow();
        scrolled.set_child(text_view);
        scrolled.vexpand = true;
        scrolled.vscrollbar_policy = Gtk.PolicyType.ALWAYS;
        scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scrolled.overlay_scrolling = false; // Scrollers were always visible
        
        // Position scrollbar on the left side
        scrolled.set_placement(Gtk.CornerType.TOP_RIGHT);
        
        return scrolled;
    }
    
    /* Find parent of specific type */
    public static T? find_parent_of_type<T>(Gtk.Widget widget) {
        Gtk.Widget? current = widget;
        while (current != null) {
            if (current is T) {
                return (T) current;
            }
            current = current.get_parent();
        }
        return null;
    }
    
    /* Find widget's root window */
    public static AcmeWindow? find_root_window(Gtk.Widget widget) {
        return widget.get_root() as AcmeWindow;
    }
}