/* textview.vala
 * Window implementation for displaying text views
 */

public class AcmeTextView : Gtk.Box {
    // Our drawing-based text view implementation
    public AcmeDrawingTextView text_view;
    public Gtk.ScrolledWindow scrolled;
    
    // Drawing-based tag line implementation
    public AcmeDrawingTextView tag_line;
    public string tag_content = "";
    
    public string filename = "Untitled";
    public Gtk.DrawingArea dirty_indicator;
    
    // Dirty state tracking
    public bool dirty = false;
    public bool initial_load = true;
    
    public bool _is_active;
    
    // Enhanced dirty state tracking
    public bool modified_since_last_save = false;
    public int64 last_save_time = 0;
    public int64 last_modification_time = 0;
    
    // Mouse chord tracking with improved timing
    public bool button1_pressed = false;
    public bool selection_active = false;
    public int64 button1_press_time = 0;
    public int button2_timeout_ms = 300; // Acme uses ~300ms timeout
    
    // Pipe command tracking
    public bool button2_clicked = false;
    public uint button2_timeout_id = 0;
    
    // Scroll handling
    public bool auto_scroll = false;
    
    // Signals
    public signal void close_requested();
    public signal void move_to_column_requested(int column_index);
    public signal void split_requested();
    public signal void file_saved();
    public signal void focus_in();
    
    // Command manager reference
    public AcmeCommandManager cmd_manager;
    
    public AcmeTextView() {
        Object(
            orientation: Gtk.Orientation.VERTICAL,
            spacing: 0
        );
        
        // Get command manager reference
        cmd_manager = AcmeCommandManager.get_instance();
        
        setup_ui();
        setup_events();
    }
    
    public void setup_ui() {
        // Create a tag bar (like ACME's tag line)
        var tag_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
        tag_box.add_css_class("acme-tag");
        
        // Create dirty indicator box and store a reference to it
        dirty_indicator = AcmeUIHelper.create_dirty_indicator(dirty);
        tag_box.append(dirty_indicator);
        
        // Set up dirty indicator as drag handle for moving windows
        setup_dirty_indicator_drag(dirty_indicator);
        
        // Create a fully editable tag line using our drawing implementation
        tag_line = new AcmeDrawingTextView(false);
        tag_line.set_size_request(-1, 16);
        tag_line.set_hexpand(true);
        
        // Style the tag line
        Gdk.RGBA tag_bg = Gdk.RGBA();
        tag_bg.parse("#E9FFFE");  // Light cyan for tags
        tag_line.set_background_color(tag_bg);
        
        Gdk.RGBA tag_bg_sel = Gdk.RGBA();
        tag_bg_sel.parse("#9eeeee");  // Dark cyan for tags' selection
        tag_line.set_selection_color(tag_bg_sel);
        
        // Add tag line to the tag box
        tag_box.append(tag_line);
        
        // Add the tag box to our main container
        this.append(tag_box);
        
        // Set up our custom mouse handling for tag bar
        setup_tag_mouse_handling(tag_line);
        
        // Set initial tag content
        setup_initial_tag();
        
        // Create the text view with drawing area
        text_view = new AcmeDrawingTextView(true);
        text_view.set_size_request(400, 300);
        text_view.set_vexpand(true);
        text_view.set_hexpand(true);
        
        // Set colors 
        Gdk.RGBA bg_color = Gdk.RGBA();
        bg_color.parse("#FFFFEA");  // ACME's yellow background
        text_view.set_background_color(bg_color);
        
        // Create scrolled window for the text view
        scrolled = new Gtk.ScrolledWindow();
        scrolled.set_child(text_view);
        scrolled.vexpand = true;
        scrolled.vscrollbar_policy = Gtk.PolicyType.ALWAYS;
        scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scrolled.overlay_scrolling = false; // Scrollers always visible
        
        // Position scrollbar on the left side
        scrolled.set_placement(Gtk.CornerType.TOP_RIGHT);
        
        // Add the scrolled window to our main container
        this.append(scrolled);
    }
    
    public void update_font(string font_name) {
        text_view.set_font(font_name);
        tag_line.set_font(font_name);
    }

    // Set up the dirty indicator as a drag handle for moving windows
    public void setup_dirty_indicator_drag(Gtk.DrawingArea indicator) {
        // Add a drag gesture to handle window movement between columns
        var drag_gesture = new Gtk.GestureDrag();
        drag_gesture.set_button(1); // Left mouse button
        indicator.add_controller(drag_gesture);
        
        // Handle drag begin
        drag_gesture.drag_begin.connect((start_x, start_y) => {
            // Claim the sequence immediately to ensure we get all events
            drag_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
            
            // Get the window
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            // Tell the window we're dragging a text view
            window.begin_textview_drag(this);
        });
        
        // Handle drag update
        drag_gesture.drag_update.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            // Update the window's drag tracking
            window.update_textview_drag(this, (int)offset_x, (int)offset_y);
        });
        
        // Handle drag end
        drag_gesture.drag_end.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            if (window == null) return;
            
            // Tell the window to end the drag operation
            window.end_textview_drag(this);
        });
        
        // Add click gestures for vertical resizing of the Acme window (textview)
        var up_click = new Gtk.GestureClick();
        up_click.set_button(1); // Left button to move up (smaller)
        indicator.add_controller(up_click);
        
        var down_click = new Gtk.GestureClick();
        down_click.set_button(3); // Right button to move down (larger)
        indicator.add_controller(down_click);
        
        // Handle clicks for vertical resizing
        up_click.pressed.connect((n_press, x, y) => {
            // Get current text view height
            int current_height = 0;
            if (scrolled != null) {
                int min_h, nat_h;
                scrolled.measure(Gtk.Orientation.VERTICAL, -1, out min_h, out nat_h, null, null);
                current_height = nat_h;
            }
            
            // Check if we're already collapsed or nearly collapsed
            if (current_height <= 20) {
                // Window is collapsed, expand it
                resize_acme_window(300);
            } else {
                // Window is expanded, collapse it
                resize_acme_window(-current_height);
            }
        });
        
        down_click.pressed.connect((n_press, x, y) => {
            // Get current text view height
            int current_height = 0;
            if (scrolled != null) {
                int min_h, nat_h;
                scrolled.measure(Gtk.Orientation.VERTICAL, -1, out min_h, out nat_h, null, null);
                current_height = nat_h;
            }
            
            // Check if we're collapsed or nearly collapsed
            if (current_height <= 20) {
                // Window is collapsed, expand it
                resize_acme_window(300);
            } else {
                // Window is already expanded, make it a bit larger
                resize_acme_window(100);
            }
        });
        
        // Add vertical drag gesture for resizing
        var vert_drag = new Gtk.GestureDrag();
        vert_drag.set_button(2); // Middle mouse button for vertical drag
        indicator.add_controller(vert_drag);
        
        vert_drag.drag_begin.connect((start_x, start_y) => {
            // Claim the sequence
            vert_drag.set_state(Gtk.EventSequenceState.CLAIMED);
        });
        
        vert_drag.drag_update.connect((offset_x, offset_y) => {
            // Handle vertical drag for window resizing
            resize_acme_window((int)offset_y);
        });
    }
    
    private void resize_acme_window(int offset) {
        // Get the current height using measure instead of allocation
        int current_height = 0;
        
        if (scrolled != null) {
            int min_h, nat_h;
            scrolled.measure(Gtk.Orientation.VERTICAL, -1, 
                            out min_h, out nat_h, null, null);
            current_height = nat_h;
        }
        
        // Calculate new height
        int new_height = current_height + offset;
        
        // Get tag bar height with proper measurement
        int tag_height = 0;
        Gtk.Widget? tag_box = get_first_child();
        if (tag_box != null) {
            int min_h, nat_h;
            tag_box.measure(Gtk.Orientation.VERTICAL, -1, 
                          out min_h, out nat_h, null, null);
            tag_height = nat_h;
        } else {
            tag_height = 16; // Default minimum
        }
        
        // Check if we're in a collapsed state (just tagbar)
        bool is_collapsed = (current_height <= 20);
        
        if (offset < 0 && new_height < 16) {
            // If reducing size and would be very small, collapse to just tag bar
            new_height = 0;
        } else if (is_collapsed && offset > 0) {
            // If currently collapsed and expanding, set to a reasonable default size
            new_height = 300;
        } else {
            // Normal resize, but ensure minimum reasonable size when expanded
            new_height = (int)Math.fmax(16, new_height);
        }
        
        // Set the height request on the scrolled window containing the text view
        if (scrolled != null) {
            scrolled.set_size_request(-1, new_height);
        }
    }
    
    public void setup_initial_tag() {
        update_tag_content_based_on_state();
    }
    
    public void update_tag_content_based_on_state() {
        StringBuilder tag_text = new StringBuilder();

        // Add filename with proper formatting
        string display_path;
        if (filename == "Untitled") {
            display_path = filename;
        } else if (filename == "+Errors") {
            display_path = filename;
        } else if (!filename.has_prefix("/")) {
            display_path = "/" + filename;
        } else {
            display_path = filename;
        }
        tag_text.append(display_path);
        
        // Determine file type and state
        bool is_directory = false;
        bool is_errors_view = (filename == "+Errors");
        bool can_undo = text_view.can_undo();
        bool can_redo = text_view.can_redo();
        
        // Check if file is a directory
        if (filename != "Untitled" && filename != "+Errors") {
            try {
                var file = File.new_for_path(filename);
                if (file.query_exists()) {
                    var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
                    is_directory = (file_info.get_file_type() == FileType.DIRECTORY);
                }
            } catch (Error e) {
                // Ignore error and assume not directory
            }
        }
        
        // Add appropriate commands based on file type and state
        if (is_directory) {
            // Directory listing - keep minimal tag line
            tag_text.append(" Del Snarf Get | Look ");
        } else if (is_errors_view) {
            // +Errors view - minimal commands
            tag_text.append(" Del | Look ");
        } else {
            // Start with basic commands
            tag_text.append(" Del Snarf");
            
            // Only show Get for unopened files - not applicable here as this is an open file
            
            // Add undo/redo if available
            if (can_undo) {
                tag_text.append(" Undo");
            }
            
            if (can_redo) {
                tag_text.append(" Redo");
            }
            
            // Add Put if file is dirty
            if (dirty) {
                tag_text.append(" Put");
            }
            
            // Add separator and Look command
            tag_text.append(" | Look ");
        }
        
        // Set the updated tag content
        tag_content = tag_text.str;
        tag_line.set_text(tag_content, true); // Position cursor at end
    }
    
    public void setup_events() {
        // Focus tracking
        var focus_controller = new Gtk.EventControllerFocus();
        focus_controller.enter.connect(() => {
            focus_in();
        });
        this.add_controller(focus_controller);
        
        // Connect to text_view's changes
        text_view.text_changed.connect(() => {
            // Don't mark as dirty during initial load
            if (!initial_load) {
                last_modification_time = get_monotonic_time();
                modified_since_last_save = true;
                
                if (!dirty) {
                    dirty = true;
                    
                    // Update the stored dirty state in the indicator widget
                    dirty_indicator.set_data("dirty_state", dirty);
                    
                    // Queue redraw of the dirty indicator
                    dirty_indicator.queue_draw();
                    
                    // Update tag content to add Put
                    update_tag_content_based_on_state();
                }
            }
        });
        
        // Update tag on undo/redo availability changes
        text_view.undo_stack_changed.connect(() => {
            update_tag_content_based_on_state();
        });
        
        text_view.redo_stack_changed.connect(() => {
            update_tag_content_based_on_state();
        });
        
        // Connect to cursor and selection signals 
        text_view.cursor_moved.connect(() => {
            // Handle cursor movement - may need to update status
        });
        
        text_view.selection_changed.connect(() => {
            // Update UI based on selection state 
        });
        
        // Add mouse interaction handling
        setup_mouse_interactions();
        
        // Initial load is complete after setup
        initial_load = false;
    }
    
    public void setup_tag_mouse_handling(AcmeDrawingTextView tag_view) {
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
                // Get selection from tag line
                string selection = tag_view.get_selected_text();
                
                if (selection != null && selection != "") {
                    // Execute the selected text as a command
                    execute_command_internal(selection);
                } else {
                    // Get word under cursor at click position by asking tag view
                    tag_view.position_cursor_at_point((int)x, (int)y);
                    string word = tag_view.get_word_at_cursor();
                    
                    if (word != null && word != "") {
                        execute_command_internal(word);
                    }
                }
            } else if (button == 3) { // Right button - look up text
                // Get selection from tag line
                string selection = tag_view.get_selected_text();
                
                if (selection != null && selection != "") {
                    // Look up the selected text
                    look_up_text(selection);
                } else {
                    // Get word under cursor at click position
                    tag_view.position_cursor_at_point((int)x, (int)y);
                    string word = tag_view.get_word_at_cursor();
                    
                    if (word != null && word != "") {
                        look_up_text(word);
                    }
                }
            }
        });
    }
    
    public void setup_mouse_interactions() {
        // Add a gesture click controller for text view
        var click = new Gtk.GestureClick();
        click.set_button(0); // Listen for any button
        text_view.add_controller(click);
        
        // Track chord state more precisely
        bool chord_cut_executed = false;
        bool chord_paste_executed = false;
        
        // Handle button press events
        click.pressed.connect((n_press, x, y) => {
            uint button = click.get_current_button();
            
            // Always claim the event to prevent default behaviors
            click.set_state(Gtk.EventSequenceState.CLAIMED);
            
            if (button == 1) { // Left click - track for chording
                button1_pressed = true;
                button1_press_time = get_monotonic_time() / 1000; // Convert to milliseconds
                
                // Store whether we have a selection
                selection_active = text_view.get_selected_text().strip() != "";
                
                // Reset chord execution flags
                chord_cut_executed = false;
                chord_paste_executed = false;
            }
            else if (button == 2) { // Middle click
                button2_clicked = true;
                
                // Set the middle button dragging flag on the text view
                text_view.set_middle_button_dragging(true);
                
                // Check for button1+button2 chord (cut)
                int64 current_time = get_monotonic_time() / 1000;
                int64 elapsed = current_time - button1_press_time;
                
                if (button1_pressed && selection_active && elapsed <= button2_timeout_ms) {
                    // This is a chord - execute cut and mark it
                    execute_cut();
                    chord_cut_executed = true;
                    
                    // Don't execute as a command since this was a chord
                    return;
                }
                
                // We'll set a timeout to clear the middle button state
                uint timeout_id = 0;
                timeout_id = Timeout.add(500, () => {
                    text_view.set_middle_button_dragging(false);
                    timeout_id = 0;
                    return false; // Don't repeat
                });
                
                // Set a timeout to clear the button2_clicked flag
                if (button2_timeout_id != 0) {
                    Source.remove(button2_timeout_id);
                }
                
                button2_timeout_id = Timeout.add(500, () => {
                    button2_clicked = false;
                    button2_timeout_id = 0;
                    return false;
                });
                
                // If this wasn't a chord, execute the selection as a command
                // BUT only if the timeout expires (meaning no chord was detected)
                Timeout.add(button2_timeout_ms + 50, () => {
                    // Only execute if no chord was detected
                    if (!chord_cut_executed) {
                        string selection = text_view.get_selected_text();
                        
                        if (selection != null && selection != "") {
                            // Execute the selected text as a command
                            execute_command_internal(selection);
                        } else {
                            // Get word under cursor
                            text_view.position_cursor_at_point((int)x, (int)y);
                            string word = text_view.get_word_at_cursor();
                            
                            if (word != null && word != "") {
                                execute_command_internal(word);
                            }
                        }
                    }
                    return false; // Don't repeat
                });
            }
            else if (button == 3) { // Right click
                // Set the right button dragging flag on the text view
                text_view.set_right_button_dragging(true);
                
                // We'll clear this flag when the button is released or after a timeout
                uint timeout_id = 0;
                timeout_id = Timeout.add(500, () => {
                    text_view.set_right_button_dragging(false);
                    timeout_id = 0;
                    return false; // Don't repeat
                });
                
                // Check for button1+button3 chord (paste over selection)
                int64 current_time = get_monotonic_time() / 1000;
                int64 elapsed = current_time - button1_press_time;
                
                if (button1_pressed && selection_active && elapsed <= button2_timeout_ms) {
                    execute_paste();
                    chord_paste_executed = true;
                    return;
                } 
                // Check for button2 then button3 (pipe command)
                else if (button2_clicked && text_view.get_selected_text().strip() != "") {
                    button2_clicked = false;
                    
                    if (button2_timeout_id != 0) {
                        Source.remove(button2_timeout_id);
                        button2_timeout_id = 0;
                    }
                    
                    // Show pipe command
                    execute_pipe_command("", text_view.get_selected_text());
                } 
                else {
                    // Regular right click - look up text
                    string selection = text_view.get_selected_text();
                    
                    if (selection != null && selection != "") {
                        look_up_text(selection);
                    } else {
                        // Position cursor at point to get word
                        text_view.position_cursor_at_point((int)x, (int)y);
                        string word = text_view.get_word_at_cursor();
                        
                        if (word != null && word != "") {
                            look_up_text(word);
                        } else {
                            // Try to get a line reference under cursor
                            string line = text_view.get_line_at_cursor();
                            
                            // Check if it's a plumbable entity
                            if (line != null && AcmePlumber.get_instance().analyze_text(line) != PlumbingType.UNKNOWN) {
                                look_up_text(line);
                            }
                        }
                    }
                }
            }
        });
        
        // Add release handler for button 1
        var release = new Gtk.GestureClick();
        release.set_button(1);
        text_view.add_controller(release);
        
        release.released.connect((n_press, x, y) => {
            button1_pressed = false;
            
            // Reset chord state when button 1 is released
            chord_cut_executed = false;
            chord_paste_executed = false;
        });

        // Rest of the existing gesture code (middle_drag, right_drag) remains the same...
        // For middle button drag interactions
        var middle_drag = new Gtk.GestureDrag();
        middle_drag.set_button(2); // Middle mouse button
        text_view.add_controller(middle_drag);
        
        middle_drag.drag_begin.connect((start_x, start_y) => {
            // Set the middle button dragging flag on the text view
            text_view.set_middle_button_dragging(true);
            
            // Start selection if needed
            text_view.position_cursor_at_point((int)start_x, (int)start_y);
            if (!text_view.has_selection) {
                text_view.start_selection();
            }
        });
        
        middle_drag.drag_update.connect((offset_x, offset_y) => {
            // Calculate the current position
            double start_x, start_y;
            middle_drag.get_start_point(out start_x, out start_y);
            double current_x = start_x + offset_x;
            double current_y = start_y + offset_y;
            
            // Update the selection
            text_view.update_selection_at_point((int)current_x, (int)current_y);
        });
        
        middle_drag.drag_end.connect((offset_x, offset_y) => {
            // Process the middle-button selection (typically execution)
            string selected_text = text_view.get_selected_text();
            if (selected_text != null && selected_text != "") {
                // Check if this was part of a chord
                if (!chord_cut_executed) {
                    // Execute the selected text as a command only if not part of a chord
                    execute_command_internal(selected_text);
                }
            }
            
            // Clear the middle button dragging state
            text_view.set_middle_button_dragging(false);
        });
        
        // For right button drag interactions
        var right_drag = new Gtk.GestureDrag();
        right_drag.set_button(3); // Right mouse button
        text_view.add_controller(right_drag);
        
        right_drag.drag_begin.connect((start_x, start_y) => {
            // Set the right button dragging flag on the text view
            text_view.set_right_button_dragging(true);
            
            // Start selection if needed
            text_view.position_cursor_at_point((int)start_x, (int)start_y);
            if (!text_view.has_selection) {
                text_view.start_selection();
            }
        });
        
        right_drag.drag_update.connect((offset_x, offset_y) => {
            // Calculate the current position
            double start_x, start_y;
            right_drag.get_start_point(out start_x, out start_y);
            double current_x = start_x + offset_x;
            double current_y = start_y + offset_y;
            
            // Update the selection
            text_view.update_selection_at_point((int)current_x, (int)current_y);
        });
        
        right_drag.drag_end.connect((offset_x, offset_y) => {
            // Process the right-button selection (typically look up)
            string selected_text = text_view.get_selected_text();
            if (selected_text != null && selected_text != "") {
                // Look up the selected text
                look_up_text(selected_text);
            }
            
            // Clear the right button dragging state
            text_view.set_right_button_dragging(false);
        });
    }
    
    // Execute a pipe command (text | shell_command)
    public void execute_pipe_command(string text, string command) {
        print("Piping text through command: %s\n", command);
        
        try {
            // Create a temporary file for stdin
            string stdin_path;
            int stdin_fd = FileUtils.open_tmp("acme-stdin-XXXXXX", out stdin_path);
            
            // Write data - using FileUtils.set_contents instead of FileUtils.write
            FileUtils.close(stdin_fd);
            FileUtils.set_contents(stdin_path, text);
            
            // Create a temporary file for stdout
            string stdout_path;
            int stdout_fd = FileUtils.open_tmp("acme-stdout-XXXXXX", out stdout_path);
            FileUtils.close(stdout_fd);
            
            // Create subprocess with better error handling
            string[] cmd_args = {"/bin/zsh", "-c", 
                @"cat \"$stdin_path\" | $command > \"$stdout_path\" 2>&1"};
                
            int exit_status;
            string std_error;
            
            Process.spawn_sync(
                null,           // Working directory
                cmd_args,       // Command and args
                null,           // Environment
                SpawnFlags.SEARCH_PATH,
                null,           // Child setup function
                null,           // Standard output
                out std_error,  // Standard error
                out exit_status // Exit status
            );
            
            // Read the output file
            string output;
            FileUtils.get_contents(stdout_path, out output);
            
            // Clean up temporary files
            FileUtils.unlink(stdin_path);
            FileUtils.unlink(stdout_path);
            
            if (exit_status == 0) {
                // Command succeeded - replace selected text with output
                if (text_view.has_selection) {
                    // Get selection range
                    text_view.delete_selection();
                    text_view.insert_text(output);
                } else {
                    // Just insert at cursor
                    text_view.insert_text(output);
                }
            } else {
                // Command failed
            }
            
        } catch (Error e) {
            warning("Error executing pipe command: %s", e.message);
        }
    }
    
    // Set active state and update styling accordingly
    public void set_active(bool active) {
        if (_is_active == active) return;
        
        _is_active = active;
    }
    
    // Check if this view is active
    public bool is_active() {
        return _is_active;
    }
    
    // Add this to get_effective_width() for debugging:
    private int get_effective_width() {
        int width = text_view.get_width();
        print("get_width() returned: %d\n", width);
        
        if (width <= 0) {
            int min_width, nat_width;
            text_view.measure(Gtk.Orientation.HORIZONTAL, -1, out min_width, out nat_width, null, null);
            width = nat_width;
            print("measure() returned natural width: %d\n", width);
        }
        
        if (width <= 0) {
            width = 485;
            print("Using default width: %d\n", width);
        }
        
        print("Final effective width: %d\n", width);
        return (int)Math.fmax(width, 200);
    }
    
    // Execute command handlers - exposed for command manager
    public void execute_cut() {
        text_view.acme_cut();
    }
    
    public void execute_paste() {
        text_view.acme_paste();
    }
    
    public void execute_snarf() {
        text_view.acme_snarf();
    }
    
    public void execute_sort() {
        // Get selected text
        string text = text_view.get_selected_text();
        if (text == null || text == "") {
            print("No text selected to sort\n");
            return;
        }
        
        // Split into lines
        string[] lines = text.split("\n");
        
        // Sort the lines
        Array<string> sorted_lines = new Array<string>();
        foreach (string line in lines) {
            sorted_lines.append_val(line);
        }
        sorted_lines.sort(strcmp);
        
        // Join back into text
        StringBuilder sorted_text = new StringBuilder();
        for (int i = 0; i < sorted_lines.length; i++) {
            sorted_text.append(sorted_lines.index(i));
            if (i < sorted_lines.length - 1) {
                sorted_text.append("\n");
            }
        }
        
        // Replace the selected text with sorted text
        text_view.delete_selection();
        text_view.insert_text(sorted_text.str);
        
        print("Text sorted\n");
    }
    
    public void execute_undo() {
        text_view.undo();
        
        // If the file becomes clean after undo, update dirty state
        if (!text_view.is_modified()) {
            dirty = false;
            dirty_indicator.set_data("dirty_state", false);
            dirty_indicator.queue_draw();
        }
        
        // Update tag content for undo/redo/put state
        update_tag_content_based_on_state();
    }

    public void execute_redo() {
        text_view.redo();
        
        // If the file becomes dirty after redo, update dirty state
        if (text_view.is_modified()) {
            dirty = true;
            dirty_indicator.set_data("dirty_state", true);
            dirty_indicator.queue_draw();
        }
        
        // Update tag content for undo/redo/put state
        update_tag_content_based_on_state();
    }
    
    public void execute_get(string path) {
        // Check if it's a directory
        var file = File.new_for_path(path);
        try {
            var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
            if (file_info.get_file_type() == FileType.DIRECTORY) {
                // It's a directory, use proportional listing
                int view_width = get_effective_width();
                
                string listing = AcmeFileHandler.get_directory_listing(path, text_view.font_desc, view_width);
                
                // Clear the buffer and insert the listing
                text_view.set_text(listing);
                
                // Update the filename
                set_filename(path);
                
                // Ensure we're scrolled to top
                text_view.scroll_to_top();
                return;
            }
        } catch (Error e) {
            // Ignore errors, just try to open as a file
        }
        
        // Load file
        string error_message = "";
        try {
            // Check if the file exists
            if (!file.query_exists()) {
                error_message = "File does not exist: " + path;
            } else {
                // Read the file content
                uint8[] contents;
                string etag_out;
                file.load_contents(null, out contents, out etag_out);
                
                // Convert bytes to string
                string text = (string) contents;
                
                // Set text content
                text_view.set_text(text);
                
                // Update the filename
                set_filename(path);
                
                // Ensure we're scrolled to top
                text_view.scroll_to_top();
            }
        } catch (Error e) {
            error_message = "Error loading file: " + e.message;
        }
    }
    
    public void execute_put(string path) {
        // If path is empty, use the current filename
        if (path == "" && filename != "Untitled") {
            path = filename;
        }
        
        // Save file
        string error_message = "";
        try {
            // Get the text content - making sure to get ALL the text
            string text = text_view.get_text();
            
            // Print for debugging
            print("Saving file %s with %d characters\n", path, text.length);
            
            // Create or overwrite the file
            var file = File.new_for_path(path);
            
            // Create parent directories if they don't exist
            var parent = file.get_parent();
            if (parent != null && !parent.query_exists()) {
                try {
                    parent.make_directory_with_parents();
                } catch (Error e) {
                    error_message = "Error creating directory: " + e.message;
                    throw e;
                }
            }
            
            // Write to the file using FileUtils for more direct control
            if (!FileUtils.set_contents(path, text)) {
                error_message = "Error writing to file: " + path;
                throw new IOError.FAILED(error_message);
            }
            
            // Record save time
            last_save_time = get_monotonic_time();
            modified_since_last_save = false;
            
            // Update the filename
            set_filename(path);
            
            // Notify user of successful save
            string message = "\nFile saved: " + path + "\n";
            text_view.insert_text(message);
            print(message);
            
            // Mark as clean and emit signal
            dirty = false;
            dirty_indicator.set_data("dirty_state", false);
            dirty_indicator.queue_draw(); // Redraw to update the dirty indicator
            file_saved();
            
            // Update tag content to reflect clean state (remove Put)
            update_tag_content_based_on_state();
        } catch (Error e) {
            if (error_message == "") {
                error_message = "Error saving file: " + e.message;
            }
            print("Error: %s\n", error_message);
            text_view.insert_text("\nError: " + error_message + "\n");
        }
    }
    
    /**
     * Execute ls command to list directory contents
     * @param path Optional directory path to list (defaults to home directory)
     */
    public void execute_ls(string? path = null) {
        // If no path specified, use home directory
        string directory_path = path;
        if (directory_path == null || directory_path == "") {
            directory_path = Environment.get_home_dir();
        }
        
        // Expand ~ to home directory if present
        if (directory_path == "~" || directory_path.has_prefix("~/")) {
            string home = Environment.get_home_dir();
            if (directory_path == "~") {
                directory_path = home;
            } else {
                directory_path = Path.build_filename(home, directory_path.substring(2));
            }
        }
        
        // Get the directory listing using proportional formatting
        int view_width = get_effective_width();
        
        string listing = AcmeFileHandler.get_directory_listing(directory_path, text_view.font_desc, view_width);
        
        // Insert the listing
        text_view.insert_text(listing);
    }

    // Updated method for window initialization
    public static void initialize_with_home_directory(AcmeTextView view) {
        // Get the user's home directory
        string home_dir = Environment.get_home_dir();
        
        print("Initializing home directory view with path: %s\n", home_dir);
        
        // Update filename first so the directory check will work
        view.update_filename(home_dir);
        
        // Execute get command to show home directory contents
        view.execute_get(home_dir);
        
        // Force correct tag line setup for directory
        view.ensure_directory_tagline();
        
        // Ensure we're scrolled to top
        view.text_view.scroll_to_top();
    }
    
    public void ensure_directory_tagline() {
        // Verify we're actually pointing to a directory
        bool is_directory = false;
        
        try {
            if (filename != "Untitled" && filename != "+Errors") {
                var file = File.new_for_path(filename);
                if (file.query_exists()) {
                    var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
                    is_directory = (file_info.get_file_type() == FileType.DIRECTORY);
                }
            }
        } catch (Error e) {
            print("Error checking if file is directory: %s\n", e.message);
        }
        
        if (is_directory) {
            // Build the proper directory tag line
            StringBuilder tag_text = new StringBuilder();
            
            // Add filename with leading slash if needed
            string display_path = filename;
            if (!display_path.has_prefix("/")) {
                display_path = "/" + display_path;
            }
            tag_text.append(display_path);
            
            // Add the proper directory commands
            tag_text.append(" Del Snarf Get | Look ");
            
            // Set the tag text
            set_tag_content(tag_text.str);
            
            print("Set directory tag line: %s\n", tag_text.str);
        }
    }
    
    // Command execution system
    public void execute_command(string command) {
        execute_command_internal(command);
    }
    
    public void execute_command_internal(string command) {
        print("Executing command: %s\n", command);
        
        // Create command context
        var context = new AcmeCommandContext.with_text_view(this);
        context.command_text = command;
        
        // Try to execute as a known command first
        if (cmd_manager.execute_command(command, context)) {
            return; // Command was handled
        }
        
        // If not a built-in command, treat as a shell command
        var window = get_root() as AcmeWindow;
        if (window == null) return;
        
        try {
            // Get the errors view first to ensure it exists
            var errors_view = window.get_errors_view();
            if (errors_view == null) return;
            
            // First display the command (only here, not in the output processing)
            window.append_command_output(command, "", false);
            
            // For real-time output capture, we'll use spawn_command_line_async 
            // with output redirection to a temp file for more compatibility
            string temp_stdout, temp_stderr;
            int stdout_fd = FileUtils.open_tmp("acme-stdout-XXXXXX", out temp_stdout);
            int stderr_fd = FileUtils.open_tmp("acme-stderr-XXXXXX", out temp_stderr);
            
            // Close the FDs since we just needed the filenames
            FileUtils.close(stdout_fd);
            FileUtils.close(stderr_fd);
            
            // Build command with redirection
            string cmd_with_redirection = 
                "%s > %s 2> %s".printf(
                    command.replace("\"", "\\\""), // Escape quotes
                    temp_stdout.replace(" ", "\\ "), // Escape spaces
                    temp_stderr.replace(" ", "\\ ")  // Escape spaces
                );
            
            // Launch the process
            string[] spawn_args = {"/bin/zsh", "-c", cmd_with_redirection};
            Pid child_pid;
            
            Process.spawn_async(
                null, // Working directory
                spawn_args,
                null, // Environment
                SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                null, // Child setup function
                out child_pid
            );
            
            // Add a variable to keep track of whether we've already processed output
            bool has_output = false;
            
            // Track the command for duplication checking
            string cmd_check = command.has_prefix("$ ") ? command : "$ " + command;
            
            // Set up file watchers - we'll poll the output files periodically
            uint stdout_watch_id = Timeout.add(100, () => {
                try {
                    // Check for content in stdout file
                    string content;
                    if (FileUtils.get_contents(temp_stdout, out content) && content.length > 0) {
                        // Set the flag indicating we've processed output
                        has_output = true;
                        
                        // Clear the file to avoid rereading the same content
                        FileUtils.set_contents(temp_stdout, "");
                        
                        // Process the content by lines
                        string[] lines = content.split("\n");
                        foreach (string line in lines) {
                            // Skip if the line is the command itself to avoid duplication
                            if (line == command || line == cmd_check || line == "") continue;
                            
                            // Only pass the line, not the command
                            window.append_command_output_line("", line, false);
                        }
                    }
                    return true; // Continue watching
                } catch (Error e) {
                    return true; // Continue watching even if there's an error
                }
            });
            
            // Similar logic for stderr
            uint stderr_watch_id = Timeout.add(100, () => {
                try {
                    // Check for content in stderr file
                    string content;
                    if (FileUtils.get_contents(temp_stderr, out content) && content.length > 0) {
                        // Set the flag indicating we've processed output
                        has_output = true;
                        
                        // Clear the file to avoid rereading the same content
                        FileUtils.set_contents(temp_stderr, "");
                        
                        // Process the content by lines
                        string[] lines = content.split("\n");
                        foreach (string line in lines) {
                            // Skip if the line is the command itself to avoid duplication
                            if (line == command || line == cmd_check || line == "") continue;
                            
                            // Only pass the line, not the command
                            window.append_command_output_line("", line, true);
                        }
                    }
                    return true; // Continue watching
                } catch (Error e) {
                    return true; // Continue watching even if there's an error
                }
            });
            
            // Watch for process completion
            ChildWatch.add(child_pid, (pid, status) => {
                // Stop the file watchers
                Source.remove(stdout_watch_id);
                Source.remove(stderr_watch_id);
                
                // One final check of the output files
                try {
                    string stdout_content, stderr_content;
                    if (FileUtils.get_contents(temp_stdout, out stdout_content) && stdout_content.length > 0) {
                        // Set the flag indicating we've processed output
                        has_output = true;
                        
                        string[] lines = stdout_content.split("\n");
                        foreach (string line in lines) {
                            // Skip if the line is the command itself to avoid duplication
                            if (line == command || line == cmd_check || line == "") continue;
                            
                            // Only pass the line, not the command
                            window.append_command_output_line("", line, false);
                        }
                    }
                    
                    if (FileUtils.get_contents(temp_stderr, out stderr_content) && stderr_content.length > 0) {
                        // Set the flag indicating we've processed output
                        has_output = true;
                        
                        string[] lines = stderr_content.split("\n");
                        foreach (string line in lines) {
                            // Skip if the line is the command itself to avoid duplication
                            if (line == command || line == cmd_check || line == "") continue;
                            
                            // Only pass the line, not the command
                            window.append_command_output_line("", line, true);
                        }
                    }
                } catch (Error e) {
                    // Ignore errors on final read
                }
                
                // Clean up temp files
                FileUtils.unlink(temp_stdout);
                FileUtils.unlink(temp_stderr);
                
                // Skip completion message if no output was produced
                if (!has_output) {
                    window.append_command_output_line("", "No output from command", false);
                }
                
                // Clean up child process
                Process.close_pid(pid);
            });
            
        } catch (Error e) {
            warning("Error executing command: %s", e.message);
            
            // Show error message in the errors view
            window.append_command_output("", "Error executing command: " + e.message, true);
        }
    }
    
    public void look_up_text(string text) {
        print("Looking up: %s\n", text);
        
        // First, check if this text is a directory entry from a directory listing
        bool is_directory_entry = text.has_suffix("/");
        
        // If it's a directory entry (ends with /), handle it
        if (is_directory_entry) {
            print("Detected directory entry: %s\n", text);
            
            // Remove trailing slash
            string dir_name = text.substring(0, text.length - 1);
            
            // Construct the full path using the current view's filename as context
            string parent_dir = filename;
            string full_path;
            
            // Check if the dir_name is an absolute path
            if (dir_name.has_prefix("/")) {
                full_path = dir_name;
            } else {
                // Ensure the parent_dir is a directory
                try {
                    var file = File.new_for_path(parent_dir);
                    if (file.query_exists()) {
                        var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
                        if (file_info.get_file_type() == FileType.DIRECTORY) {
                            // Parent is a directory, build path as parent/child
                            full_path = Path.build_filename(parent_dir, dir_name);
                        } else {
                            // Parent is a file, use its containing directory
                            string parent_of_parent = Path.get_dirname(parent_dir);
                            full_path = Path.build_filename(parent_of_parent, dir_name);
                        }
                    } else {
                        // Fall back to current directory if parent doesn't exist
                        full_path = Path.build_filename(".", dir_name);
                    }
                } catch (Error e) {
                    // On error, try using current directory
                    full_path = Path.build_filename(".", dir_name);
                    print("Error checking parent directory: %s\n", e.message);
                }
            }
            
            print("Opening directory: %s\n", full_path);
            
            // Open the directory in a new view
            open_file_in_new_view(full_path);
            return;
        }
        
        // Check if the current view is a directory listing
        bool is_directory_view = false;
        string current_dir = "";
        
        try {
            var file = File.new_for_path(filename);
            if (file.query_exists()) {
                var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
                is_directory_view = (file_info.get_file_type() == FileType.DIRECTORY);
                if (is_directory_view) {
                    current_dir = filename;
                    print("We're in a directory view: %s\n", current_dir);
                }
            }
        } catch (Error e) {
            print("Error checking if current view is directory: %s\n", e.message);
        }
        
        // If we're in a directory view, check if clicked text matches a file in the directory
        if (is_directory_view && current_dir != "") {
            // Get the text up to the first space - filenames don't contain spaces
            string base_text = text;
            int space_pos = text.index_of(" ");
            if (space_pos > 0) {
                base_text = text.substring(0, space_pos);
            }
            
            print("Looking for files matching: %s\n", base_text);
            
            // First check for exact match
            string exact_path = Path.build_filename(current_dir, base_text);
            var exact_file = File.new_for_path(exact_path);
            if (exact_file.query_exists()) {
                print("Found exact match: %s\n", exact_path);
                open_file_in_new_view(exact_path);
                return;
            }
            
            // Now scan the directory for files that start with this text
            try {
                var dir = File.new_for_path(current_dir);
                var enumerator = dir.enumerate_children("standard::*", FileQueryInfoFlags.NONE);
                
                // Keep track of all matching files
                string[] matching_files = {};
                
                FileInfo info;
                while ((info = enumerator.next_file()) != null) {
                    string name = info.get_name();
                    
                    // Check if this file starts with our base text
                    if (name.has_prefix(base_text)) {
                        // Check that the next character is either a dot (for extension) or nothing
                        if (name.length == base_text.length || name[base_text.length:base_text.length+1] == ".") {
                            string matched_path = Path.build_filename(current_dir, name);
                            print("Found matching file: %s\n", matched_path);
                            matching_files += matched_path;
                        }
                    }
                }
                
                // If we found exactly one match, open it
                if (matching_files.length == 1) {
                    print("Opening unique match: %s\n", matching_files[0]);
                    open_file_in_new_view(matching_files[0]);
                    return;
                }
                // If we found multiple matches, prefer exact base name + extension
                else if (matching_files.length > 1) {
                    foreach (string matched_path in matching_files) {
                        string filename_only = Path.get_basename(matched_path);
                        if (filename_only.has_prefix(base_text + ".")) {
                            print("Found best match: %s\n", matched_path);
                            open_file_in_new_view(matched_path);
                            return;
                        }
                    }
                    // If we couldn't find a clear best match, use the first one
                    print("Using first match: %s\n", matching_files[0]);
                    open_file_in_new_view(matching_files[0]);
                    return;
                }
            } catch (Error e) {
                print("Error scanning directory: %s\n", e.message);
            }
            
            print("No matching file found for: %s\n", base_text);
        }
        
        // If we get here, it's not a file in the current directory listing
        
        // Check if it looks like a search pattern
        if (text.length >= 1 && (text[0] == '/' || !text.contains(" "))) {
            // Try to use the search system
            if (AcmeSearch.get_instance().execute_look(text, this)) {
                return;
            }
        }
        
        // Try to use the plumber to handle the text
        var plumber = AcmePlumber.get_instance();
        if (plumber.plumb_text(text, this)) {
            return;
        }
        
        // If nothing else handled it, try to execute as a command
        print("Executing command: %s\n", text);
        execute_command_internal(text);
    }

    // Method to open a file in a new view within the same column
    private void open_file_in_new_view(string filepath) {
        print("Opening file in new view: %s\n", filepath);
        
        // Find the parent column
        AcmeColumn? parent_column = null;
        Gtk.Widget? widget = this;
        
        while (widget != null && !(widget is AcmeColumn)) {
            widget = widget.get_parent();
        }
        
        if (widget != null) {
            parent_column = widget as AcmeColumn;
        } else {
            print("Error: Could not find parent column\n");
            return;
        }
        
        try {
            // First check if it's a file or directory
            var file = File.new_for_path(filepath);
            if (!file.query_exists()) {
                print("File does not exist: %s\n", filepath);
                return;
            }
            
            var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
            bool is_directory = (file_info.get_file_type() == FileType.DIRECTORY);
            
            // Create a new text view
            var new_view = new AcmeTextView();
            
            // Add it to the column first so it's in the UI hierarchy
            parent_column.add_text_view(new_view);
            
            // Use the existing methods to load content based on type
            if (is_directory) {
                print("Loading directory: %s\n", filepath);
                // Update filename first
                new_view.update_filename(filepath);
                
                // Execute get command - which is designed to properly handle directories
                new_view.execute_get(filepath);
                
                // Ensure tag line is set up for directory
                new_view.ensure_directory_tagline();
                
                // Ensure we're scrolled to top
                new_view.text_view.scroll_to_top();
            } else {
                print("Loading file: %s\n", filepath);
                // Use the execute_get method which is specifically designed to load files
                new_view.execute_get(filepath);
            }
        } catch (Error e) {
            print("Error in open_file_in_new_view: %s\n", e.message);
        }
    }
    
    // Get the filename for this text view
    public string get_filename() {
        return filename;
    }
    
    // Get the TextView widget
    public Gtk.Widget get_text_view() {
        return text_view;
    }
    
    // Check if this text view has unsaved changes
    public bool is_dirty() {
        return dirty;
    }
    
    // Check modification status with timestamp
    public bool is_modified_since_save() {
        return modified_since_last_save && (last_modification_time > last_save_time);
    }
    
    // Update filename from outside the class
    public void update_filename(string new_filename) {
        // Update filename
        filename = new_filename;
        
        // Reset dirty state after changing file
        dirty = false;
        dirty_indicator.set_data("dirty_state", false);
        dirty_indicator.queue_draw(); // Redraw to update the dirty indicator
        
        // Update tag content based on the new file state
        update_tag_content_based_on_state();
    }
    
    // Get tag content
    public string get_tag_content() {
        return tag_content;
    }
    
    // Set tag content
    public void set_tag_content(string content) {
        tag_content = content;
        tag_line.set_text(content, true);
    }
    
    // Set auto-scrolling behavior
    public void set_real_time_scrolling(bool enable) {
        auto_scroll = enable;
    }
    
    // Scroll to end of buffer
    public void scroll_to_end() {
        if (auto_scroll) {
            text_view.scroll_to_end();
        }
    }
    
    // Method to scroll the view to a specific line and column
    public void scroll_to_line_column(int line, int column) {
        text_view.scroll_to_line_column(line, column);
    }
    
    public void set_filename(string new_filename) {
        filename = new_filename;
        
        // Reset dirty state after changing file
        dirty = false;
        dirty_indicator.set_data("dirty_state", false);
        dirty_indicator.queue_draw(); // Redraw to update the dirty indicator
        
        // Update tag content based on the new file state
        update_tag_content_based_on_state();
    }
}