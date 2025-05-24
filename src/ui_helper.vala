/* ui_helper.vala
 * UI helper functions
 */

/* Simple callback delegates */
public delegate void DirtyChangedCallback(bool is_dirty);
public delegate void SimpleCallback();

/* UI helper class */
public class AcmeUIHelper : Object {
    
    /**
     * Create a dirty indicator drawing area
     */
    public static Gtk.DrawingArea create_dirty_indicator(bool initial_dirty_state, bool is_column = false) {
        var indicator = new Gtk.DrawingArea();
        indicator.set_size_request(12, 16);
        
        // Store state in widget data
        indicator.set_data("dirty_state", initial_dirty_state);
        indicator.set_data("is_column", is_column);
        
        // Set draw function with simplified rendering
        indicator.set_draw_func((drawing_area, context, width, height) => {
            draw_dirty_indicator(drawing_area, context, width, height);
        });

        return indicator;
    }
    
    private static void draw_dirty_indicator(Gtk.DrawingArea area, Cairo.Context cr, int width, int height) {
        bool is_dirty = area.get_data<bool>("dirty_state");
        bool is_column = area.get_data<bool>("is_column");
        
        // Set crisp 1px lines
        cr.set_antialias(Cairo.Antialias.NONE);
        
        // Get theme colors
        var border_color = AcmeThemeManager.get_window_border_color();
        
        // Draw border
        cr.set_source_rgb(border_color.red, border_color.green, border_color.blue);
        cr.set_line_width(2.0);
        cr.rectangle(1.0, 1.0, width - 2.0, height - 2.0);
        cr.stroke();
        
        // Fill based on state
        if (is_column || is_dirty) {
            if (is_column) {
                // Columns always fill with border color
                cr.set_source_rgb(border_color.red, border_color.green, border_color.blue);
            } else {
                // Dirty windows use darker blue
                cr.set_source_rgb(0.0, 0.0, 0.6);
            }
            
            cr.rectangle(1.0, 1.0, width - 3.0, height - 3.0);
            cr.fill();
        }
    }
    
    /**
     * Create a command label with click handler
     */
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
    
    /**
     * Set up keyboard shortcuts for text entry
     */
    public static void setup_text_keymap(Gtk.Entry entry, owned SimpleCallback on_enter) {
        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect((controller, keyval, keycode, state) => {
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                on_enter();
                return true;
            }
            return false;
        });
        entry.add_controller(key_controller);
    }

    /**
     * Create scrolled window with Acme-style scrollbar positioning
     */
    public static Gtk.ScrolledWindow create_text_scrolled_window(Gtk.TextView text_view) {
        var scrolled = new Gtk.ScrolledWindow();
        scrolled.set_child(text_view);
        scrolled.vexpand = true;
        scrolled.vscrollbar_policy = Gtk.PolicyType.ALWAYS;
        scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scrolled.overlay_scrolling = false;
        
        // Position scrollbar on the left side (Acme style)
        scrolled.set_placement(Gtk.CornerType.TOP_RIGHT);
        
        return scrolled;
    }
    
    /**
     * Find parent widget of specific type
     */
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
    
    /**
     * Find widget's root window
     */
    public static AcmeWindow? find_root_window(Gtk.Widget? widget) {
        if (widget == null) return null;
        return widget.get_root() as AcmeWindow;
    }
    
    /**
     * Create a simple dialog window
     */
    public static Gtk.Window create_dialog(string title, Gtk.Window? parent = null) {
        var dialog = new Gtk.Window();
        dialog.set_title(title);
        dialog.set_modal(true);
        
        if (parent != null) {
            dialog.set_transient_for(parent);
        }
        
        return dialog;
    }
    
    /**
     * Create a button box with standard spacing
     */
    public static Gtk.Box create_button_box(bool homogeneous = true) {
        var box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        box.homogeneous = homogeneous;
        box.margin_top = 12;
        return box;
    }
    
    /**
     * Add margins to a widget
     */
    public static void add_margins(Gtk.Widget widget, int margin = 12) {
        widget.margin_start = margin;
        widget.margin_end = margin;
        widget.margin_top = margin;
        widget.margin_bottom = margin;
    }
    
    /**
     * Set widget size with reasonable defaults
     */
    public static void set_size_request_with_defaults(Gtk.Widget widget, int width = -1, int height = -1) {
        // Use reasonable defaults if not specified
        if (width == -1) width = 300;
        if (height == -1) height = -1; // Let height be natural
        
        widget.set_size_request(width, height);
    }
}