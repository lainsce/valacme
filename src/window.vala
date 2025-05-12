/* window.vala
 * Root window implementation
 */

public class AcmeWindow : Gtk.ApplicationWindow {
    private Gtk.Box main_box;
    private Gtk.Box root_box;
    private List<AcmeColumn> columns;
    
    public AcmeDrawingTextView main_tag_line;
    public string tag_content = "";
    
    // Column operations state
    private AcmeColumn? resize_column = null;
    private int resize_start_width = 0;
    private int resize_start_mouse_x = 0;
    
    private AcmeColumn? reorder_column = null;
    private int reorder_original_index = -1;

    // Textview operations state
    private AcmeTextView? dragging_textview = null;
    private AcmeColumn? target_column = null;
    private double drag_start_x = 0;
    
    // Command manager reference
    private AcmeCommandManager cmd_manager;
    
    // Errors view reference
    private AcmeTextView? errors_view = null;
    
    public AcmeWindow (Gtk.Application app) {
        Object (
            application: app,
            title: "Valacme",
            default_width: 1215,
            default_height: 810
        );
        
        // Initialize the column list
        columns = new List<AcmeColumn> ();
        
        // Get command manager reference
        cmd_manager = AcmeCommandManager.get_instance();
        
        // Set up the window
        setup_ui ();
    }
    
    private void setup_ui () {
        // Create main content box
        root_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        this.set_child (root_box);
        
        // Create the main tag bar box
        var main_tag_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        main_tag_box.add_css_class ("acme-main-tag");
        
        // Create a fully editable main tag line
        main_tag_line = new AcmeDrawingTextView(false);
        main_tag_line.set_hexpand(true);
        main_tag_line.set_size_request(-1, 16);

        // Style the tag line
        Gdk.RGBA tag_bg = Gdk.RGBA();
        tag_bg.parse("#E9FFFE");  // Light cyan for tags
        main_tag_line.set_background_color(tag_bg);
        
        Gdk.RGBA tag_bg_sel = Gdk.RGBA();
        tag_bg_sel.parse("#9eeeee");  // Dark cyan for tags' selection
        main_tag_line.set_selection_color(tag_bg_sel);
        
        // Add tag line to the main tag box
        main_tag_box.append (main_tag_line);
        
        // Set up our custom mouse handling for tag bar
        setup_tag_mouse_handling(main_tag_line);
        
        // Set initial tag content
        setup_initial_tag();
        
        // Add tag line to root
        root_box.append (main_tag_box);
        
        // Create a box to hold our columns
        main_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        main_box.vexpand = true;
        root_box.append (main_box);
        
        // Add keyboard controller to main_box
        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            // Handle global keyboard shortcuts
            return false;
        });
        main_box.add_controller(key_controller);
        
        // Create our first columns
        initialize_authentic_layout();
    }
    
    public void setup_initial_tag() {
        StringBuilder tag_text = new StringBuilder();

        tag_text.append("Newcol Kill Putall Dump Exit ");
        tag_content = tag_text.str;
        main_tag_line.set_text(tag_content, true); // Position cursor at end
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
                // Get word under cursor at click position by asking tag view
                tag_view.position_cursor_at_point((int)x, (int)y);
                string word = tag_view.get_word_at_cursor();
                
                if (word != null && word != "") {
                    switch(word) {
                        case "Newcol":
                            on_newcol_clicked ();
                            break;
                        case "Kill":
                            on_kill_clicked ();
                            break;
                        case "Putall":
                            on_putall_clicked ();
                            break;
                        case "Dump":
                            on_dump_clicked ();
                            break;
                        case "Load":
                            on_load_clicked ();
                            break;
                        case "Exit":
                            on_exit_clicked ();
                            break;
                    }
                }
            }
        });
    }
    
    /**
     * Initialize with authentic Acme layout: empty left column and home directory in right column
     */
    private void initialize_authentic_layout() {
        // Create left column (empty)
        var left_column = new AcmeColumn();
        main_box.append(left_column);
        columns.append(left_column);
        
        // Handle column close request
        left_column.close_requested.connect(() => {
            handle_column_close(left_column);
        });
        
        // Create right column with home directory listing
        var right_column = new AcmeColumn();
        main_box.append(right_column);
        columns.append(right_column);
        
        // Handle column close request
        right_column.close_requested.connect(() => {
            handle_column_close(right_column);
        });
        
        // Add a text view to the right column
        var text_view = new AcmeTextView();
        right_column.add_text_view(text_view);
        
        // Initialize with home directory
        AcmeTextView.initialize_with_home_directory(text_view);
        
        // Ensure proper tag line is set
        text_view.ensure_directory_tagline();
        
        // Set column widths to divide the columns as the original
        int total_width = 1215; // Window width directly
        int left_col_width = total_width - 485;
        
        right_column.set_size_request(485, -1);
        left_column.set_size_request(left_col_width, -1);
        
        // Update column borders
        update_column_borders();
    }
    
    /**
     * Update column borders based on their positions
     * This ensures only interior columns have right borders
     */
    private void update_column_borders() {
        var theme_manager = AcmeThemeManager.get_instance();
        uint column_count = columns.length();
        
        for (int i = 0; i < column_count; i++) {
            var column = columns.nth_data(i);
            bool is_rightmost = (i == column_count - 1);
            
            // Apply the appropriate border style
            theme_manager.apply_column_border_style(column, is_rightmost);
        }
    }
    
    public AcmeColumn? get_last_column() {
        if (columns.length() > 0) {
            return columns.nth_data(columns.length() - 1);
        }
        return null;
    }

    
    // Command callbacks
    public void on_newcol_clicked () {
        add_column ();
    }
    
    public void on_putall_clicked () {
        // Save all modified files
        bool any_saved = false;
        
        // Go through all columns and text views
        foreach (var column in columns) {
            // Get content box
            var content_box = column.get_content_box ();
            var child = content_box.get_first_child ();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView) child;
                    
                    // Only save if the text view is dirty and has a filename
                    if (text_view.is_dirty () && text_view.get_filename () != "Untitled") {
                        var context = new AcmeCommandContext.with_text_view(text_view);
                        cmd_manager.execute_command("Put", context);
                        any_saved = true;
                    }
                }
                
                child = child.get_next_sibling ();
            }
        }
        
        if (!any_saved) {
            print ("No modified files to save\n");
        }
    }
    
    public void on_kill_clicked () {
        // Implementation of Kill command - kill a process or window
        // Create a modern window-based dialog instead of deprecated Gtk.Dialog
        var dialog_window = new Gtk.Window();
        dialog_window.set_title("Kill Command");
        dialog_window.set_modal(true);
        dialog_window.set_transient_for(this);
        dialog_window.set_default_size(300, -1);
        
        // Create a main box for content
        var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        main_box.margin_start = 12;
        main_box.margin_end = 12;
        main_box.margin_top = 12;
        main_box.margin_bottom = 12;
        dialog_window.set_child(main_box);
        
        // Create a grid for the content
        var grid = new Gtk.Grid();
        grid.row_spacing = 6;
        grid.column_spacing = 6;
        main_box.append(grid);
        
        // Label for process ID
        var pid_label = new Gtk.Label("Process ID:");
        pid_label.halign = Gtk.Align.START;
        grid.attach(pid_label, 0, 0, 1, 1);
        
        // Entry for process ID
        var pid_entry = new Gtk.Entry();
        pid_entry.hexpand = true;
        grid.attach(pid_entry, 1, 0, 1, 1);
        
        // Button box
        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        button_box.homogeneous = true;
        button_box.margin_top = 12;
        main_box.append(button_box);
        
        // Add buttons
        var cancel_button = new Gtk.Button.with_label("Cancel");
        var kill_button = new Gtk.Button.with_label("Kill");
        kill_button.add_css_class("destructive-action");
        
        button_box.append(cancel_button);
        button_box.append(kill_button);
        
        // Connect signals
        cancel_button.clicked.connect(() => {
            dialog_window.destroy();
        });
        
        kill_button.clicked.connect(() => {
            string pid_text = pid_entry.get_text();
            if (pid_text != "") {
                int pid = int.parse(pid_text);
                execute_kill_command(pid);
            }
            dialog_window.destroy();
        });
        
        // Show dialog
        dialog_window.present();
    }
    
    private void execute_kill_command(int pid) {
        try {
            // Create a new subprocess to run the kill command
            var subprocess = new Subprocess (
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE,
                "kill", pid.to_string ()
            );
            
            // Start the subprocess
            subprocess.wait_async.begin (null, (obj, res) => {
                try {
                    subprocess.wait_async.end (res);
                    print ("Process %d killed\n", pid);
                } catch (Error e) {
                    warning ("Error killing process %d: %s", pid, e.message);
                }
            });
        } catch (Error e) {
            warning ("Error starting kill command: %s", e.message);
        }
    }
    
    public void on_dump_clicked() {
        // Implementation of Dump command - save editor state to CSV
        try {
            // Get home directory
            string home_dir = Environment.get_home_dir();
            string save_dir = Path.build_filename(home_dir, ".local", "share", "acme-vala");
            
            // Create directory structure if it doesn't exist
            var dir = File.new_for_path(save_dir);
            if (!dir.query_exists()) {
                dir.make_directory_with_parents();
            }
            
            // Create CSV file
            string csv_path = Path.build_filename(save_dir, "acme_dump.csv");
            var file = File.new_for_path(csv_path);
            var stream = file.replace(null, false, FileCreateFlags.NONE);
            
            // Create a data stream for writing
            var data_stream = new DataOutputStream(stream);
            
            // Write CSV header with cursor/selection info
            data_stream.put_string("column_index,window_index,filename,cursor_line,cursor_col,selection_start_line,selection_start_col,selection_end_line,selection_end_col,has_selection,tag_content\n");
            
            // Iterate through all columns and windows
            for (int col_idx = 0; col_idx < columns.length(); col_idx++) {
                var column = columns.nth_data(col_idx);
                var window_index = 0;
                
                // Get content box
                var content_box = column.get_content_box();
                var child = content_box.get_first_child();
                
                while (child != null) {
                    if (child is AcmeTextView) {
                        var text_view = (AcmeTextView)child;
                        var filename = text_view.get_filename();
                        
                        // Get cursor position from drawing text view
                        int cursor_line = text_view.text_view.cursor_line;
                        int cursor_col = text_view.text_view.cursor_col;
                        
                        // Get selection bounds from drawing text view
                        bool has_selection = text_view.text_view.has_selection;
                        int selection_start_line = text_view.text_view.selection_start_line;
                        int selection_start_col = text_view.text_view.selection_start_col;
                        int selection_end_line = text_view.text_view.selection_end_line;
                        int selection_end_col = text_view.text_view.selection_end_col;
                        
                        // Get tag line content
                        string tag_content = text_view.get_tag_content();
                        
                        // Write window state to CSV with updated fields
                        data_stream.put_string("%d,%d,%s,%d,%d,%d,%d,%d,%d,%s,%s\n".printf(
                            col_idx,
                            window_index,
                            filename,
                            cursor_line,
                            cursor_col,
                            selection_start_line,
                            selection_start_col,
                            selection_end_line,
                            selection_end_col,
                            has_selection ? "true" : "false",
                            tag_content
                        ));
                        
                        window_index++;
                    }
                    
                    child = child.get_next_sibling();
                }
            }
            
            // Also save column tag contents
            for (int col_idx = 0; col_idx < columns.length(); col_idx++) {
                var column = columns.nth_data(col_idx);
                string tag_content = column.get_tag_content();
                
                // Write column tag to special entries (window_index = -1)
                data_stream.put_string("%d,%d,%s,%d,%d,%d,%d,%d,%d,%s,%s\n".printf(
                    col_idx,
                    -1,  // Indicates column tag
                    "Column",
                    0, 0, 0, 0, 0, 0,
                    "false",
                    tag_content
                ));
            }
            
            print("Editor state dumped to %s\n", csv_path);
        } catch (Error e) {
            warning("Error dumping editor state: %s", e.message);
        }
    }
    
    public void on_load_clicked() {
        // Implementation of Load command - restore editor state from dump
        try {
            // Get home directory
            string home_dir = Environment.get_home_dir();
            string save_dir = Path.build_filename(home_dir, ".local", "share", "acme-vala");
            string csv_path = Path.build_filename(save_dir, "acme_dump.csv");
            
            // Check if dump file exists
            var file = File.new_for_path(csv_path);
            if (!file.query_exists()) {
                warning("Dump file does not exist: %s", csv_path);
                return;
            }
            
            // Clear current state
            // Close all columns except the first one
            while (columns.length() > 1) {
                var column = columns.nth_data(1);
                main_box.remove(column);
                columns.remove(column);
            }
            
            // Clear the first column's text views
            var first_column = columns.nth_data(0);
            var content_box = first_column.get_content_box();
            var child = content_box.get_first_child();
            while (child != null) {
                var next_child = child.get_next_sibling();
                content_box.remove(child);
                child = next_child;
            }
            
            // Read the CSV file
            uint8[] content_data;
            string etag_out;
            file.load_contents(null, out content_data, out etag_out);
            string contents = (string)content_data;
            
            // Parse the CSV data
            string[] lines = contents.split("\n");
            if (lines.length < 2) {
                warning("Invalid dump file format");
                return;
            }
            
            // Skip header line
            // Create a dictionary to store columns by index
            var column_dict = new HashTable<int, AcmeColumn>(direct_hash, direct_equal);
            column_dict.insert(0, first_column);
            
            // Process each line
            for (int i = 1; i < lines.length; i++) {
                string line = lines[i].strip();
                if (line == "") continue;
                
                string[] parts = line.split(",", 11);  // Updated to handle all fields
                if (parts.length < 11) continue;
                
                int col_idx = int.parse(parts[0]);
                int win_idx = int.parse(parts[1]);
                string filename = parts[2];
                int cursor_line = int.parse(parts[3]);
                int cursor_col = int.parse(parts[4]);
                int selection_start_line = int.parse(parts[5]);
                int selection_start_col = int.parse(parts[6]);
                int selection_end_line = int.parse(parts[7]);
                int selection_end_col = int.parse(parts[8]);
                bool has_selection = parts[9] == "true";
                string tag_content = parts[10];
                
                // Check if this is a column tag entry
                if (win_idx == -1) {
                    // Handle column tag
                    if (column_dict.contains(col_idx)) {
                        var column = column_dict.get(col_idx);
                        column.set_tag_content(tag_content);
                    }
                    continue;
                }
                
                // Get or create the column
                AcmeColumn column;
                if (column_dict.contains(col_idx)) {
                    column = column_dict.get(col_idx);
                } else {
                    // Create a new column
                    column = new AcmeColumn();
                    main_box.append(column);
                    columns.append(column);
                    
                    // Handle column close request
                    column.close_requested.connect(() => {
                        handle_column_close(column);
                    });
                    
                    column_dict.insert(col_idx, column);
                }
                
                // Create a text view
                var text_view = new AcmeTextView();
                column.add_text_view(text_view);
                
                // Load the file if it's not "Untitled"
                if (filename != "Untitled") {
                    text_view.execute_get(filename);
                }
                
                // Set cursor position on drawing text view
                text_view.text_view.cursor_line = cursor_line;
                text_view.text_view.cursor_col = cursor_col;
                
                // Set selection if applicable
                if (has_selection) {
                    text_view.text_view.has_selection = true;
                    text_view.text_view.selection_start_line = selection_start_line;
                    text_view.text_view.selection_start_col = selection_start_col;
                    text_view.text_view.selection_end_line = selection_end_line;
                    text_view.text_view.selection_end_col = selection_end_col;
                } else {
                    text_view.text_view.has_selection = false;
                }
                
                // Set tag content
                text_view.set_tag_content(tag_content);
                
                // Ensure cursor is visible
                text_view.text_view.ensure_cursor_visible();
                text_view.text_view.queue_draw();
            }
            
            print("Editor state loaded from %s\n", csv_path);
        } catch (Error e) {
            warning("Error loading editor state: %s", e.message);
        }
    }
    
    public void on_exit_clicked() {
        // Check for unsaved changes
        if (has_unsaved_changes()) {
            //
        } else {
            // Exit immediately if no unsaved changes
            this.close();
        }
    }
    
    public void update_all_fonts(string font_name) {
        // Update main tag line font
        main_tag_line.set_font(font_name);
        
        // Update all column tag lines
        foreach (var column in columns) {
            column.tag_line.set_font(font_name);
            
            // Get content box
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            // Update all text views in the column
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView)child;
                    text_view.text_view.set_font(font_name);
                    text_view.tag_line.set_font(font_name);
                }
                child = child.get_next_sibling();
            }
        }
    }
    
    // Check for unsaved changes across all text views
    private bool has_unsaved_changes() {
        foreach (var column in columns) {
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView)child;
                    if (text_view.is_dirty() && text_view.is_modified_since_save()) {
                        return true;
                    }
                }
                child = child.get_next_sibling();
            }
        }
        
        return false;
    }
    
    private void add_column() {
        var column = new AcmeColumn();
        main_box.append(column);
        columns.append(column);
        
        // Handle column close request
        column.close_requested.connect(() => {
            handle_column_close(column);
        });
        
        // Add a text view to the new column
        var text_view = new AcmeTextView();
        column.add_text_view(text_view);
        
        // Update column borders
        update_column_borders();
    }
    
    private void handle_column_close(AcmeColumn column) {
        // Only allow closing if there's more than one column
        if (columns.length() > 1) {
            // Get all text views and try to move them to other columns
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView)child;
                    // Get the previous child before removing it
                    var next_child = child.get_next_sibling();
                    content_box.remove(child);
                    
                    // Find another column to move the text view to
                    for (int i = 0; i < columns.length(); i++) {
                        if (columns.nth_data(i) != column) {
                            columns.nth_data(i).add_text_view(text_view);
                            break;
                        }
                    }
                    
                    child = next_child;
                } else {
                    child = child.get_next_sibling();
                }
            }
            
            // Now remove the column
            main_box.remove(column);
            columns.remove(column);
            
            // Update column borders
            update_column_borders();
        } else {
            // Don't allow closing the last column
            warning("Cannot close the last column");
        }
    }
    
    // Column resize handling
    public void begin_column_resize(AcmeColumn column, int x, int y) {
        resize_column = column;
        
        // Store the starting column width
        resize_start_width = column.get_width();
        
        // Store the exact position where resize started
        var surface = get_surface();
        if (surface != null) {
            var seat = display.get_default_seat();
            if (seat != null) {
                var pointer = seat.get_pointer();
                double mouse_x, mouse_y;
                surface.get_device_position(pointer, out mouse_x, out mouse_y, null);
                resize_start_mouse_x = (int)mouse_x;
            }
        }
        
        // Change cursor to indicate resize
        var cursor = new Gdk.Cursor.from_name("resize", null);
        if (surface != null) {
            surface.set_cursor(cursor);
        }
    }

    // Update column width during drag
    public void update_column_resize(AcmeColumn column, int offset_x) {
        // Only proceed if we're resizing this column
        if (resize_column != column) return;
        
        // Calculate new width based on start width and mouse delta
        // We want the column to get wider when dragging right and narrower when dragging left
        // Determine current mouse position
        var surface = get_surface();
        if (surface != null) {
            var seat = display.get_default_seat();
            if (seat != null) {
                var pointer = seat.get_pointer();
                double current_mouse_x, current_mouse_y;
                surface.get_device_position(pointer, out current_mouse_x, out current_mouse_y, null);
                
                // Calculate delta from starting mouse position
                int delta = (int)(current_mouse_x - resize_start_mouse_x);
                
                // Calculate new width - IMPORTANT: resize column should get narrower
                // when mouse moves RIGHT (position in array increases)
                // This is authentic to Plan 9 Acme behavior
                int new_width = resize_start_width - delta;
                
                // Ensure minimum width (prevents resizing to zero or negative)
                new_width = (int)Math.fmax(new_width, 100);
                
                // Apply the new width
                resize_column.set_size_request(new_width, -1);
            }
        }
    }

    // End column resize operation
    public void end_column_resize(AcmeColumn column) {
        // Only proceed if we're resizing this column
        if (resize_column != column) return;
        
        // Reset cursor
        var surface = get_surface();
        if (surface != null) {
            surface.set_cursor(null);
        }
        
        // Clear all resize state
        resize_column = null;
        resize_start_width = 0;
        resize_start_mouse_x = 0;
    }
    
    // Begin column reorder operation
    public void begin_column_reorder(AcmeColumn column, int x, int y) {
        reorder_column = column;
        
        // Find the index of the column in our list
        reorder_original_index = -1;
        for (int i = 0; i < columns.length(); i++) {
            if (columns.nth_data(i) == column) {
                reorder_original_index = i;
                break;
            }
        }
        
        // Change cursor to indicate grabbing
        var cursor = new Gdk.Cursor.from_name("grab", null);
        var surface = get_surface();
        if (surface != null) {
            surface.set_cursor(cursor);
        }
    }

    // End column reorder operation
    public void end_column_reorder(AcmeColumn column, int offset_x) {
        if (reorder_column != column || reorder_original_index < 0) return;
        
        // Determine target index based on drag direction
        int target_index = reorder_original_index;
        
        // Simple algorithm: move one position left or right based on direction
        if (offset_x > 20 && reorder_original_index < columns.length() - 1) {
            // Moved right - increase index by 1
            target_index = reorder_original_index + 1;
        } else if (offset_x < -20 && reorder_original_index > 0) {
            // Moved left - decrease index by 1
            target_index = reorder_original_index - 1;
        }
        
        // Only reorder if the index changed
        if (target_index != reorder_original_index) {
            // Get the column we're moving
            var moving_column = columns.nth_data(reorder_original_index);
            
            // Remove from its current position
            main_box.remove(moving_column);
            columns.remove(moving_column);
            
            // Insert at the new position
            if (target_index >= columns.length()) {
                // Add to the end
                main_box.append(moving_column);
                columns.append(moving_column);
            } else {
                // In GTK4, we need to first add the widget, then reorder it
                if (target_index == 0) {
                    // If moving to the start, use prepend
                    main_box.prepend(moving_column);
                } else {
                    // Otherwise, add to the end first
                    main_box.append(moving_column);
                    
                    // Then reorder it to the right position
                    // Get the column that should be before our column
                    var before_col = columns.nth_data(target_index - 1);
                    
                    // Reorder to be after this column
                    main_box.reorder_child_after(moving_column, before_col);
                }
                
                // Insert into the list at the right position
                columns.insert(moving_column, target_index);
            }
            
            // Update column borders
            update_column_borders();
        }
        
        // Reset cursor
        var surface = get_surface();
        if (surface != null) {
            surface.set_cursor(null);
        }
        
        // Clear state
        reorder_column = null;
        reorder_original_index = -1;
    }
    
    /**
     * Begin dragging a text view between columns
     */
    public void begin_textview_drag(AcmeTextView textview) {
        dragging_textview = textview;
        
        // Record the starting x position using compute_point instead of translate_coordinates
        Graphene.Point point = {};
        bool success = textview.compute_point(this, Graphene.Point.zero(), out point);
        drag_start_x = success ? point.x : 0;
    }

    /**
     * Update text view drag position - only track target column
     */
    public void update_textview_drag(AcmeTextView textview, int offset_x, int offset_y) {
        if (dragging_textview != textview) return;

        // Calculate current position based on start position + offset
        double current_x = drag_start_x + offset_x;
        
        // Find column under current position
        target_column = null;
        
        foreach (var column in columns) {
            // Get column position and size using modern methods
            int col_width = column.get_width();
            
            Graphene.Point point = {};
            column.compute_point(this, Graphene.Point.zero(), out point);
            double col_x = point.x;
            
            // Check if position is over this column
            if (current_x >= col_x && current_x < col_x + col_width) {
                target_column = column;
                break;
            }
        }
    }

    /**
     * End text view drag and perform the move if appropriate
     */
    public void end_textview_drag(AcmeTextView textview) {
        if (dragging_textview != textview) return;
        
        // Find the source column
        Gtk.Widget? parent = textview;
        AcmeColumn? source_column = null;
        
        while (parent != null && !(parent is AcmeColumn)) {
            parent = parent.get_parent();
        }
        
        if (parent != null) {
            source_column = (AcmeColumn)parent;
        }
        
        // If we have both source and target columns, perform the move
        if (source_column != null && target_column != null && source_column != target_column) {
            // Remove from current parent
            var content_box = source_column.get_content_box();
            content_box.remove(textview);
            
            // Add to target column
            target_column.add_text_view(textview);
        }
        
        // Reset state
        dragging_textview = null;
        target_column = null;
    }
    
    // Find or create the +Errors view for command output
    public AcmeTextView get_errors_view() {
        // If we already have an errors view, return it
        if (errors_view != null) {
            // Make sure the errors view is still in the UI hierarchy
            if (errors_view.get_parent() != null) {
                // Ensure scrolling follows output
                errors_view.set_real_time_scrolling(true);
                return errors_view;
            }
            errors_view = null; // Reset if it was removed
        }
        
        // Try to find an existing +Errors view in any column
        foreach (var column in columns) {
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView)child;
                    if (text_view.get_filename() == "+Errors") {
                        errors_view = text_view;
                        // Ensure scrolling follows output
                        errors_view.set_real_time_scrolling(true);
                        
                        // Position cursor at the end to ensure new text is appended
                        errors_view.text_view.cursor_line = errors_view.text_view.line_count - 1;
                        errors_view.text_view.cursor_col = errors_view.text_view.lines[errors_view.text_view.line_count - 1].length;
                        
                        return errors_view;
                    }
                }
                child = child.get_next_sibling();
            }
        }
        
        // Create a new +Errors view in the last column
        var last_column = columns.nth_data(columns.length() - 1);
        errors_view = new AcmeTextView();
        errors_view.update_filename("+Errors");
        
        // Ensure scrolling follows output - this is crucial
        errors_view.set_real_time_scrolling(true);
        
        // Add to the column
        last_column.add_text_view(errors_view);
        
        return errors_view;
    }
    
    // Append command output to the errors view
    public void append_command_output(string command, string output, bool is_error = false) {
        var errors = get_errors_view();
        
        if (errors == null) return;
        
        // Get the text view directly
        var text_view = errors.text_view;
        
        // Build the formatted output text
        StringBuilder formatted_text = new StringBuilder();
        
        // Add a single newline only if needed
        if (text_view.line_count > 1 && text_view.lines[text_view.line_count - 1].length > 0) {
            formatted_text.append("\n");
        }
        
        // Add the command with proper formatting
        if (command != "") {
            // Check if command already has a prefix
            if (command.has_prefix("$ ")) {
                formatted_text.append(command);
            } else {
                formatted_text.append("$ ");
                formatted_text.append(command);
            }
            
            // Add a newline after the command
            formatted_text.append("\n");
        }
        
        // Add output text if any
        if (output != "") {
            formatted_text.append(output);
        }
        
        // Insert the text at the current cursor position
        text_view.insert_text(formatted_text.str);
        
        // Ensure the view scrolls to the end
        text_view.scroll_to_end();
    }
    
    // Append a single line of command output
    public void append_command_output_line(string command, string line, bool is_error) {
        // Skip empty lines to avoid extra newlines
        if (line == "") return;
        
        // Skip if the line is just the command (avoids duplication)
        if (line == command || line == "$ " + command) return;
        
        var errors = get_errors_view();
        if (errors == null) return;
        
        // Get the text view directly
        var text_view = errors.text_view;
        
        // Insert the line with a newline
        text_view.insert_text(line + "\n");
        
        // Ensure the view scrolls to the end
        text_view.scroll_to_end();
    }
    
    // Utility methods
    public List<AcmeTextView> get_all_text_views() {
        var result = new List<AcmeTextView>();
        
        foreach (var column in columns) {
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    result.append((AcmeTextView)child);
                }
                child = child.get_next_sibling();
            }
        }

        return (owned)result;
    }
    
    // Other methods
    public void move_text_view_to_column(AcmeTextView view, int column_index) {
        // Check if the column index is valid
        if (column_index < 0 || column_index >= columns.length()) {
            warning("Invalid column index: %d", column_index);
            return;
        }
        
        // Get the target column
        var target_column = columns.nth_data(column_index);
        
        // Get the current parent
        var current_parent = view.get_parent();
        if (current_parent == null) {
            warning("Text view has no parent");
            return;
        }
        
        // Remove from current parent
        ((Gtk.Box)current_parent).remove(view);
        
        // Add to target column
        target_column.add_text_view(view);
    }
    
    public void split_text_view(AcmeTextView view) {
        // Create a new column
        var new_column = new AcmeColumn();
        main_box.append(new_column);
        columns.append(new_column);
        
        // Handle column close request
        new_column.close_requested.connect(() => {
            handle_column_close(new_column);
        });
        
        // Remove the view from its current parent
        var current_parent = view.get_parent();
        if (current_parent != null) {
            ((Gtk.Box)current_parent).remove(view);
        }
        
        // Add the view to the new column
        new_column.add_text_view(view);
    }
}