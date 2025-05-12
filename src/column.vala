/* column.vala
 * Column implementation for organizing text views
 */

public class AcmeColumn : Gtk.Box {
    private Gtk.Box content_box;
    private Gtk.Box header_box;
    private Gtk.DrawingArea dirty_indicator;
    
    // Active window tracking
    private AcmeTextView? active_window = null;
    
    // Signals
    public signal void close_requested();
    public signal void resize_started(int x, int y);
    public signal void drag_started(int x, int y);
    public signal void drag_ended();
    
    // Clipboard for snarf/paste operations
    private Gdk.Clipboard clipboard;
    
    // Track if any window in this column has unsaved changes
    private bool has_unsaved_changes = false;
    
    // Command manager reference
    private AcmeCommandManager cmd_manager;
    
    public AcmeDrawingTextView tag_line;
    public string tag_content = "";
    public int column_width = 250;
    
    public AcmeColumn() {
        Object(
            orientation: Gtk.Orientation.VERTICAL,
            spacing: 0
        );
        
        // Get the clipboard for snarf/paste operations
        clipboard = Gdk.Display.get_default().get_clipboard();
        
        // Get command manager reference
        cmd_manager = AcmeCommandManager.get_instance();
        setup_ui();
    }
    
    private void setup_ui() {
        // Create a header for the column
        header_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
        header_box.add_css_class("acme-column-header");
        
        // Create the dirty indicator box - pass true as second parameter to indicate it's a column
        dirty_indicator = AcmeUIHelper.create_dirty_indicator(has_unsaved_changes, true);
        header_box.append(dirty_indicator);
        
        // Set up mouse handling on dirty indicator for Plan9-style resize and reorder
        setup_dirty_indicator_handling(dirty_indicator);
        
        // Create a fully editable tag line
        tag_line = new AcmeDrawingTextView(false);
        tag_line.set_hexpand(true);
        tag_line.set_size_request(-1, 16);
        
        // Style the tag line
        Gdk.RGBA tag_bg = Gdk.RGBA();
        tag_bg.parse("#E9FFFE");  // Light cyan for tags
        tag_line.set_background_color(tag_bg);
        
        Gdk.RGBA tag_bg_sel = Gdk.RGBA();
        tag_bg_sel.parse("#9eeeee");  // Dark cyan for tags' selection
        tag_line.set_selection_color(tag_bg_sel);
        
        // Set initial tag content with standard commands
        setup_initial_tag();
        
        // Add tag line to the header box
        header_box.append(tag_line);
        
        // Add the header to our column
        this.append(header_box);
        
        // Set up mouse handling on header for Plan9-style interaction
        setup_header_mouse_handling(tag_line);
        
        // Create the box to hold our text views
        content_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 2);
        content_box.vexpand = true;
        
        // Add the content box to our column
        this.append(content_box);
    }
    
    public void update_font(string font_name) {
        tag_line.set_font(font_name);
    }
    
    private void setup_dirty_indicator_handling(Gtk.DrawingArea indicator) {
        // Create separate gesture controllers for each button
        
        // Left button gesture for column reordering
        var left_drag = new Gtk.GestureDrag();
        left_drag.set_button(1); // Explicitly set to left mouse button
        indicator.add_controller(left_drag);
        
        // Right button gesture for column resizing
        var right_drag = new Gtk.GestureDrag();
        right_drag.set_button(3); // Explicitly set to right mouse button
        indicator.add_controller(right_drag);
        
        // Handle left button drag (reordering)
        left_drag.drag_begin.connect((start_x, start_y) => {
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            // Ensure we get all drag events
            left_drag.set_state(Gtk.EventSequenceState.CLAIMED);
            
            window.begin_column_reorder(this, (int)start_x, (int)start_y);
        });
        
        // No update handler needed for reordering - we only care about final position
        
        left_drag.drag_end.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            window.end_column_reorder(this, (int)offset_x);
        });

        // Handle right button drag (resizing)
        right_drag.drag_begin.connect((start_x, start_y) => {
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            // Ensure we get all drag events
            right_drag.set_state(Gtk.EventSequenceState.CLAIMED);
            
            // Transform coordinates to window space
            Graphene.Point window_point = {};
            bool success = indicator.compute_point(
                window,
                { x: (float)start_x, y: (float)start_y },
                out window_point
            );
            
            int win_x = success ? (int)window_point.x : (int)start_x;
            int win_y = success ? (int)window_point.y : (int)start_y;
            
            window.begin_column_resize(this, win_x, win_y);
        });
        
        right_drag.drag_update.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            window.update_column_resize(this, (int)offset_x);
        });
        
        right_drag.drag_end.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            window.end_column_resize(this);
        });
    }
    
    private void setup_initial_tag() {
        StringBuilder tag_text = new StringBuilder();

        tag_text.append("New Cut Paste Snarf Sort Zerox Delcol ");
        tag_content = tag_text.str;
        tag_line.set_text(tag_content, true); // Position cursor at end
    }
    
    private void setup_header_mouse_handling(AcmeDrawingTextView tag_view) {
        // Add a gesture click controller to handle mouse button clicks on tag line
        var click = new Gtk.GestureClick();
        click.set_button(0); // Listen for any button
        tag_view.add_controller(click);
        
        // Handle button press events on tag line
        click.pressed.connect((n_press, x, y) => {
            uint button = click.get_current_button();
            
            // Always claim the event
            click.set_state(Gtk.EventSequenceState.CLAIMED);
            
            if (button == 2) { // Middle button - execute selected text
                // Get word under cursor at click position by asking tag view
                tag_view.position_cursor_at_point((int)x, (int)y);
                string word = tag_view.get_word_at_cursor();
                
                if (word != null && word != "") {
                    execute_command(word);
                }
            }
        });
    }
    
    // Execute command for the column context
    private void execute_command(string command) {
        var context = new AcmeCommandContext.with_column(this);
        context.command_text = command;
        cmd_manager.execute_command(command, context);
    }
    
    // Set the dirty state and update the indicator
    public void set_dirty(bool dirty) {
        if (has_unsaved_changes != dirty) {
            has_unsaved_changes = dirty;
            
            // Update the stored dirty state in the indicator widget
            dirty_indicator.set_data("dirty_state", dirty);
            
            // Request redraw of the indicator
            dirty_indicator.queue_draw();
        }
    }
    
    // Command implementations - now accessible for command manager
    public void on_new_clicked() {
        // Create a new text view in this column
        var text_view = new AcmeTextView();
        add_text_view(text_view);
    }
    
    public void on_cut_clicked() {
        // Find the active text view and cut selected text
        if (active_window != null) {
            active_window.execute_cut();
        } else {
            print("No active window to cut from\n");
        }
    }
    
    public void on_paste_clicked() {
        // Find the active text view and paste text
        if (active_window != null) {
            active_window.execute_paste();
        } else {
            print("No active window to paste to\n");
        }
    }
    
    public void on_snarf_clicked() {
        // Find the active text view and copy selected text
        if (active_window != null) {
            active_window.execute_snarf();
        } else {
            print("No active window to snarf from\n");
        }
    }
    
    public void on_sort_clicked() {
        // Find the active text view and sort selected lines
        if (active_window != null) {
            active_window.execute_sort();
        } else {
            print("No active window to sort\n");
        }
    }
    
    public void on_zerox_clicked() {
        // Create a duplicate of the active text view
        if (active_window != null) {
            // Create a new text view
            var new_view = new AcmeTextView();
            
            // Copy content from active window's text widget
            string text = active_window.text_view.get_text();
            new_view.text_view.set_text(text);
            
            // Set the same filename
            string filename = active_window.get_filename();
            if (filename != "Untitled") {
                new_view.update_filename(filename + " (copy)");
            }
            
            // Add to column
            add_text_view(new_view);
        } else {
            print("No active window to duplicate\n");
        }
    }
    
    public void on_delcol_clicked() {
        // Delete this column
        close_requested();
    }
    
    public void add_text_view(AcmeTextView view) {
        content_box.append(view);
        view.vexpand = true;
        
        // Set as active window when added
        set_active_window(view);
        
        // Connect to focus events to track active window
        view.focus_in.connect(() => {
            set_active_window(view);
        });
        
        // Connect to the view's save signal to clear dirty state
        view.file_saved.connect(() => {
            // Check if all text views are now clean
            update_dirty_state();
        });
        
        // Connect to the view's close request
        view.close_requested.connect(() => {
            content_box.remove(view);
            
            // If this was the active window, clear it
            if (active_window == view) {
                active_window = null;
                
                // Try to find another window to make active
                var child = content_box.get_first_child();
                while (child != null) {
                    if (child is AcmeTextView) {
                        set_active_window((AcmeTextView)child);
                        break;
                    }
                    child = child.get_next_sibling();
                }
            }
            
            // Update dirty state after removing the view
            update_dirty_state();
            
            // If this was the last view, close the column
            if (content_box.get_first_child() == null) {
                close_requested();
            }
        });
        
        // Connect to the view's move request
        view.move_to_column_requested.connect((column_index) => {
            // Find the target column
            var window = (AcmeWindow)get_root();
            if (window != null) {
                window.move_text_view_to_column(view, column_index);
                
                // Update dirty state after moving the view
                update_dirty_state();
            }
        });
        
        // Connect to the view's split request
        view.split_requested.connect(() => {
            // Find the window
            var window = (AcmeWindow)get_root();
            if (window != null) {
                window.split_text_view(view);
                
                // Update dirty state after splitting
                update_dirty_state();
            }
        });
    }
    
    // Set the active window in this column
    private void set_active_window(AcmeTextView view) {
        // If already active, do nothing
        if (active_window == view) {
            return;
        }
        
        // Update active window tracking
        active_window = view;
        
        // Highlight active window with a different background
        var child = content_box.get_first_child();
        while (child != null) {
            if (child is AcmeTextView) {
                AcmeTextView text_view = (AcmeTextView)child;
                
                if (text_view == active_window) {
                    text_view.set_active(true);
                } else {
                    text_view.set_active(false);
                }
            }
            
            child = child.get_next_sibling();
        }
    }
    
    // Update the dirty state by checking all text views
    private void update_dirty_state() {
        bool any_dirty = false;
        
        // Check each text view in this column
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
        
        // Update column dirty state
        set_dirty(any_dirty);
    }
    
    // Get tag content
    public string get_tag_content() {
        return tag_line.get_text();
    }
    
    // Set tag content
    public void set_tag_content(string content) {
        tag_line.set_text(content, true); // Position cursor at end
    }
    
    // Getter for content box (needed for Dump command)
    public Gtk.Box get_content_box() {
        return content_box;
    }
}