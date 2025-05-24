/* column.vala
 * Column implementation for organizing text views
 */

public class AcmeColumn : Gtk.Box {
    private Gtk.Box content_box;
    private Gtk.Box header_box;
    private Gtk.DrawingArea dirty_indicator;
    
    // State tracking
    private AcmeTextView? active_window = null;
    private bool has_unsaved_changes = false;
    
    // Components
    public AcmeDrawingTextView tag_line;
    public string tag_content = "";
    public int column_width = 250;
    
    // Services
    private Gdk.Clipboard clipboard;
    private AcmeCommandManager cmd_manager;
    
    // Signals
    public signal void close_requested();
    public signal void resize_started(int x, int y);
    public signal void drag_started(int x, int y);
    public signal void drag_ended();
    
    public AcmeColumn() {
        Object(
            orientation: Gtk.Orientation.VERTICAL,
            spacing: 0
        );
        
        clipboard = Gdk.Display.get_default().get_clipboard();
        cmd_manager = AcmeCommandManager.get_instance();
        setup_ui();
    }
    
    private void setup_ui() {
        // Create header
        header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
        header_box.add_css_class("acme-column-header");
        
        // Dirty indicator
        dirty_indicator = AcmeUIHelper.create_dirty_indicator(has_unsaved_changes, true);
        header_box.append(dirty_indicator);
        setup_dirty_indicator_handling(dirty_indicator);
        
        // Tag line
        tag_line = new AcmeDrawingTextView(false);
        tag_line.set_hexpand(true);
        tag_line.set_size_request(-1, 16);
        
        // Style tag line
        Gdk.RGBA tag_bg = Gdk.RGBA();
        tag_bg.parse("#E9FFFE");
        tag_line.set_background_color(tag_bg);
        
        Gdk.RGBA tag_bg_sel = Gdk.RGBA();
        tag_bg_sel.parse("#9eeeee");
        tag_line.set_selection_color(tag_bg_sel);
        
        setup_initial_tag();
        header_box.append(tag_line);
        this.append(header_box);
        
        setup_header_mouse_handling(tag_line);
        
        // Content box for text views
        content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        content_box.vexpand = true;
        this.append(content_box);
    }
    
    public void update_font(string font_name) {
        tag_line.set_font(font_name);
    }
    
    // Simplified dirty indicator handling
    private void setup_dirty_indicator_handling(Gtk.DrawingArea indicator) {
        // Left button for reordering
        var left_drag = new Gtk.GestureDrag();
        left_drag.set_button(1);
        indicator.add_controller(left_drag);
        
        left_drag.drag_begin.connect((start_x, start_y) => {
            left_drag.set_state(Gtk.EventSequenceState.CLAIMED);
            var window = get_root() as AcmeWindow;
            window?.begin_column_reorder(this, (int)start_x, (int)start_y);
        });
        
        left_drag.drag_end.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            window?.end_column_reorder(this, (int)offset_x);
        });

        // Right button for resizing
        var right_drag = new Gtk.GestureDrag();
        right_drag.set_button(3);
        indicator.add_controller(right_drag);
        
        right_drag.drag_begin.connect((start_x, start_y) => {
            right_drag.set_state(Gtk.EventSequenceState.CLAIMED);
            
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            Graphene.Point window_point = {};
            bool success = indicator.compute_point(window,
                { x: (float)start_x, y: (float)start_y }, out window_point);
            
            int win_x = success ? (int)window_point.x : (int)start_x;
            int win_y = success ? (int)window_point.y : (int)start_y;
            
            window.begin_column_resize(this, win_x, win_y);
        });
        
        right_drag.drag_update.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            window?.update_column_resize(this, (int)offset_x);
        });
        
        right_drag.drag_end.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            window?.end_column_resize(this);
        });
    }
    
    private void setup_initial_tag() {
        tag_content = "New Cut Paste Snarf Sort Zerox Delcol ";
        tag_line.set_text(tag_content, true);
    }
    
    private void setup_header_mouse_handling(AcmeDrawingTextView tag_view) {
        var click = new Gtk.GestureClick();
        click.set_button(0);
        tag_view.add_controller(click);
        
        click.pressed.connect((n_press, x, y) => {
            uint button = click.get_current_button();
            click.set_state(Gtk.EventSequenceState.CLAIMED);
            
            if (button == 2) { // Middle button - execute command
                tag_view.position_cursor_at_point((int)x, (int)y);
                string word = tag_view.get_word_at_cursor();
                
                if (word != "") {
                    execute_command(word);
                }
            }
        });
    }
    
    private void execute_command(string command) {
        var context = new AcmeCommandContext.with_column(this);
        context.command_text = command;
        cmd_manager.execute_command(command, context);
    }
    
    public void set_dirty(bool dirty) {
        if (has_unsaved_changes != dirty) {
            has_unsaved_changes = dirty;
            dirty_indicator.set_data("dirty_state", dirty);
            dirty_indicator.queue_draw();
        }
    }
    
    // Command implementations - simplified and focused
    public void on_new_clicked() {
        var text_view = new AcmeTextView();
        add_text_view(text_view);
    }
    
    public void on_cut_clicked() {
        active_window?.execute_cut();
    }
    
    public void on_paste_clicked() {
        active_window?.execute_paste();
    }
    
    public void on_snarf_clicked() {
        active_window?.execute_snarf();
    }
    
    public void on_sort_clicked() {
        active_window?.execute_sort();
    }
    
    public void on_zerox_clicked() {
        if (active_window == null) {
            print("No active window to duplicate\n");
            return;
        }
        
        var new_view = new AcmeTextView();
        
        // Copy content
        string text = active_window.text_view.get_text();
        new_view.text_view.set_text(text);
        
        // Set filename with copy suffix
        string filename = active_window.get_filename();
        if (filename != "Untitled") {
            new_view.update_filename(filename + " (copy)");
        }
        
        add_text_view(new_view);
    }
    
    public void on_delcol_clicked() {
        close_requested();
    }
    
    // Text view management - simplified
    public void add_text_view(AcmeTextView view) {
        view.add_css_class("acme-text-window");
    
        content_box.append(view);
        view.vexpand = true;
        
        set_active_window(view);
        connect_text_view_signals(view);
        update_dirty_state();
    }
    
    private void connect_text_view_signals(AcmeTextView view) {
        // Focus tracking
        view.focus_in.connect(() => {
            set_active_window(view);
        });
        
        // State change tracking
        view.file_saved.connect(() => {
            update_dirty_state();
        });
        
        // Close handling
        view.close_requested.connect(() => {
            handle_text_view_close(view);
        });
        
        // Movement requests
        view.move_to_column_requested.connect((column_index) => {
            var window = (AcmeWindow)get_root();
            window?.move_text_view_to_column(view, column_index);
            update_dirty_state();
        });
        
        view.split_requested.connect(() => {
            var window = (AcmeWindow)get_root();
            window?.split_text_view(view);
            update_dirty_state();
        });
    }
    
    private void handle_text_view_close(AcmeTextView view) {
        content_box.remove(view);
        
        // Update active window
        if (active_window == view) {
            active_window = find_next_active_window();
        }
        
        update_dirty_state();
        
        // Close column if no views left
        if (content_box.get_first_child() == null) {
            close_requested();
        }
    }
    
    private AcmeTextView? find_next_active_window() {
        var child = content_box.get_first_child();
        while (child != null) {
            if (child is AcmeTextView) {
                return (AcmeTextView)child;
            }
            child = child.get_next_sibling();
        }
        return null;
    }
    
    private void set_active_window(AcmeTextView view) {
        if (active_window == view) return;
        
        active_window = view;
        
        // Update visual state of all text views
        var child = content_box.get_first_child();
        while (child != null) {
            if (child is AcmeTextView) {
                AcmeTextView text_view = (AcmeTextView)child;
                text_view.set_active(text_view == active_window);
            }
            child = child.get_next_sibling();
        }
    }
    
    private void update_dirty_state() {
        bool any_dirty = false;
        
        var child = content_box.get_first_child();
        while (child != null) {
            if (child is AcmeTextView) {
                var text_view = (AcmeTextView)child;
                if (text_view.is_dirty()) {
                    any_dirty = true;
                    break;
                }
            }
            child = child.get_next_sibling();
        }
        
        set_dirty(any_dirty);
    }
    
    // Accessor methods
    public string get_tag_content() {
        return tag_line.get_text();
    }
    
    public void set_tag_content(string content) {
        tag_line.set_text(content, true);
    }
    
    public Gtk.Box get_content_box() {
        return content_box;
    }
}