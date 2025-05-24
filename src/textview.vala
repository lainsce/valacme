/* textview.vala
 * Window implementation for displaying text views
 */

public class AcmeTextView : Gtk.Box {
    // Core components
    public AcmeDrawingTextView text_view;
    public Gtk.ScrolledWindow scrolled;
    public AcmeDrawingTextView tag_line;
    public Gtk.DrawingArea dirty_indicator;
    
    // State
    public string filename = "Untitled";
    public string tag_content = "";
    public bool dirty = false;
    public bool initial_load = true;
    public bool _is_active;
    
    // Enhanced dirty state tracking
    public bool modified_since_last_save = false;
    public int64 last_save_time = 0;
    public int64 last_modification_time = 0;
    
    // Mouse interaction state - simplified
    public struct MouseState {
        bool button1_pressed;
        bool selection_active;
        int64 button1_press_time;
        bool button2_clicked;
        uint button2_timeout_id;
        int button2_timeout_ms;
        
        public void reset() {
            button1_pressed = false;
            selection_active = false;
            button2_clicked = false;
            if (button2_timeout_id != 0) {
                Source.remove(button2_timeout_id);
                button2_timeout_id = 0;
            }
        }
    }
    private MouseState mouse_state;
    
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
        
        cmd_manager = AcmeCommandManager.get_instance();
        mouse_state = MouseState();
        mouse_state.button2_timeout_ms = 300;
        
        setup_ui();
        setup_events();
    }
    
    public void setup_ui() {
        // Create tag bar
        var tag_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 4);
        tag_box.add_css_class("acme-tag");
        
        // Dirty indicator
        dirty_indicator = AcmeUIHelper.create_dirty_indicator(dirty);
        tag_box.append(dirty_indicator);
        setup_dirty_indicator_drag(dirty_indicator);
        
        // Tag line
        tag_line = new AcmeDrawingTextView(false);
        tag_line.set_size_request(-1, 16);
        tag_line.set_hexpand(true);
        
        // Style tag line
        Gdk.RGBA tag_bg = Gdk.RGBA();
        tag_bg.parse("#E9FFFE");
        tag_line.set_background_color(tag_bg);
        
        Gdk.RGBA tag_bg_sel = Gdk.RGBA();
        tag_bg_sel.parse("#9eeeee");
        tag_line.set_selection_color(tag_bg_sel);
        
        tag_box.append(tag_line);
        this.append(tag_box);
        
        // Set up tag mouse handling
        setup_tag_mouse_handling(tag_line);
        setup_initial_tag();
        
        // Create text view
        text_view = new AcmeDrawingTextView(true);
        text_view.set_size_request(400, 300);
        text_view.set_vexpand(true);
        text_view.set_hexpand(true);
        
        // Style text view
        Gdk.RGBA bg_color = Gdk.RGBA();
        bg_color.parse("#FFFFEA");
        text_view.set_background_color(bg_color);
        
        // Create scrolled window
        scrolled = new Gtk.ScrolledWindow();
        scrolled.set_child(text_view);
        scrolled.vexpand = true;
        scrolled.vscrollbar_policy = Gtk.PolicyType.ALWAYS;
        scrolled.hscrollbar_policy = Gtk.PolicyType.NEVER;
        scrolled.overlay_scrolling = false;
        scrolled.set_placement(Gtk.CornerType.TOP_RIGHT);
        
        this.append(scrolled);
    }
    
    public void update_font(string font_name) {
        text_view.set_font(font_name);
        tag_line.set_font(font_name);
    }

    // Simplified dirty indicator drag setup
    public void setup_dirty_indicator_drag(Gtk.DrawingArea indicator) {
        // Window movement
        var drag_gesture = new Gtk.GestureDrag();
        drag_gesture.set_button(1);
        indicator.add_controller(drag_gesture);
        
        drag_gesture.drag_begin.connect((start_x, start_y) => {
            drag_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
            var window = get_root() as AcmeWindow;
            window?.begin_textview_drag(this);
        });
        
        drag_gesture.drag_update.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            window?.update_textview_drag(this, (int)offset_x, (int)offset_y);
        });
        
        drag_gesture.drag_end.connect((offset_x, offset_y) => {
            var window = get_root() as AcmeWindow;
            window?.end_textview_drag(this);
        });
        
        // Vertical resizing clicks
        var up_click = new Gtk.GestureClick();
        up_click.set_button(1);
        indicator.add_controller(up_click);
        
        var down_click = new Gtk.GestureClick();
        down_click.set_button(3);
        indicator.add_controller(down_click);
        
        up_click.pressed.connect((n_press, x, y) => {
            resize_acme_window(get_current_height() <= 20 ? 300 : -get_current_height());
        });
        
        down_click.pressed.connect((n_press, x, y) => {
            resize_acme_window(get_current_height() <= 20 ? 300 : 100);
        });
        
        // Vertical drag resizing
        var vert_drag = new Gtk.GestureDrag();
        vert_drag.set_button(2);
        indicator.add_controller(vert_drag);
        
        vert_drag.drag_update.connect((offset_x, offset_y) => {
            resize_acme_window((int)offset_y);
        });
    }
    
    private int get_current_height() {
        if (scrolled == null) return 0;
        int min_h, nat_h;
        scrolled.measure(Gtk.Orientation.VERTICAL, -1, out min_h, out nat_h, null, null);
        return nat_h;
    }
    
    private void resize_acme_window(int offset) {
        int current_height = get_current_height();
        int new_height = current_height + offset;
        
        // Handle collapse/expand logic
        if (offset < 0 && new_height < 16) {
            new_height = 0; // Collapse
        } else if (current_height <= 20 && offset > 0) {
            new_height = 300; // Expand
        } else {
            new_height = (int)Math.fmax(16, new_height);
        }
        
        scrolled?.set_size_request(-1, new_height);
    }
    
    public void setup_initial_tag() {
        update_tag_content_based_on_state();
    }
    
    // Simplified tag content update
    public void update_tag_content_based_on_state() {
        var tag_text = new StringBuilder();

        // Add filename
        string display_path = get_display_path();
        tag_text.append(display_path);
        
        // Determine file type and state
        bool is_directory = check_if_directory();
        bool is_errors_view = (filename == "+Errors");
        bool can_undo = text_view.can_undo();
        bool can_redo = text_view.can_redo();
        
        // Add appropriate commands
        if (is_directory) {
            tag_text.append(" Del Snarf Get | Look ");
        } else if (is_errors_view) {
            tag_text.append(" Del | Look ");
        } else {
            tag_text.append(" Del Snarf");
            
            if (can_undo) tag_text.append(" Undo");
            if (can_redo) tag_text.append(" Redo");
            if (dirty) tag_text.append(" Put");
            
            tag_text.append(" | Look ");
        }
        
        tag_content = tag_text.str;
        tag_line.set_text(tag_content, true);
    }
    
    private string get_display_path() {
        if (filename == "Untitled" || filename == "+Errors") {
            return filename;
        } else if (!filename.has_prefix("/")) {
            return "/" + filename;
        } else {
            return filename;
        }
    }
    
    private bool check_if_directory() {
        if (filename == "Untitled" || filename == "+Errors") return false;
        
        try {
            var file = File.new_for_path(filename);
            if (file.query_exists()) {
                var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
                return (file_info.get_file_type() == FileType.DIRECTORY);
            }
        } catch (Error e) {
            // Ignore error
        }
        return false;
    }
    
    public void setup_events() {
        // Focus tracking
        var focus_controller = new Gtk.EventControllerFocus();
        focus_controller.enter.connect(() => { focus_in(); });
        this.add_controller(focus_controller);
        
        // Text view changes
        text_view.text_changed.connect(() => {
            if (!initial_load) {
                last_modification_time = get_monotonic_time();
                modified_since_last_save = true;
                
                if (!dirty) {
                    dirty = true;
                    dirty_indicator.set_data("dirty_state", dirty);
                    dirty_indicator.queue_draw();
                    update_tag_content_based_on_state();
                }
            }
        });
        
        // Undo/redo state changes
        text_view.undo_stack_changed.connect(() => { update_tag_content_based_on_state(); });
        text_view.redo_stack_changed.connect(() => { update_tag_content_based_on_state(); });
        
        text_view.cursor_moved.connect(() => { /* Handle cursor movement */ });
        text_view.selection_changed.connect(() => { /* Update UI based on selection */ });
        
        setup_mouse_interactions();
        initial_load = false;
    }
    
    public void setup_tag_mouse_handling(AcmeDrawingTextView tag_view) {
        var click = new Gtk.GestureClick();
        click.set_button(0);
        tag_view.add_controller(click);
        
        click.pressed.connect((n_press, x, y) => {
            uint button = click.get_current_button();
            click.set_state(Gtk.EventSequenceState.CLAIMED);
            
            if (button == 2) { // Middle button - execute
                execute_tag_command(tag_view, (int)x, (int)y);
            } else if (button == 3) { // Right button - look up
                look_up_tag_text(tag_view, (int)x, (int)y);
            }
        });
    }
    
    private void execute_tag_command(AcmeDrawingTextView tag_view, int x, int y) {
        string selection = tag_view.get_selected_text();
        
        if (selection != "") {
            execute_command_internal(selection);
        } else {
            tag_view.position_cursor_at_point(x, y);
            string word = tag_view.get_word_at_cursor();
            if (word != "") {
                execute_command_internal(word);
            }
        }
    }
    
    private void look_up_tag_text(AcmeDrawingTextView tag_view, int x, int y) {
        string selection = tag_view.get_selected_text();
        
        if (selection != "") {
            look_up_text(selection);
        } else {
            tag_view.position_cursor_at_point(x, y);
            string word = tag_view.get_word_at_cursor();
            if (word != "") {
                look_up_text(word);
            }
        }
    }
    
    // Simplified mouse interaction setup
    public void setup_mouse_interactions() {
        var click = new Gtk.GestureClick();
        click.set_button(0);
        text_view.add_controller(click);
        
        // Unified click handler with chord detection
        click.pressed.connect((n_press, x, y) => {
            uint button = click.get_current_button();
            click.set_state(Gtk.EventSequenceState.CLAIMED);
            
            handle_button_press(button, x, y);
        });
        
        // Button 1 release handler
        var release = new Gtk.GestureClick();
        release.set_button(1);
        text_view.add_controller(release);
        
        release.released.connect((n_press, x, y) => {
            mouse_state.reset();
        });

        // Drag gestures for each button
        setup_drag_gestures();
    }
    
    private void handle_button_press(uint button, double x, double y) {
        if (button == 1) { // Left click
            mouse_state.button1_pressed = true;
            mouse_state.button1_press_time = get_monotonic_time() / 1000;
            mouse_state.selection_active = text_view.get_selected_text().strip() != "";
        }
        else if (button == 2) { // Middle click
            handle_middle_button(x, y);
        }
        else if (button == 3) { // Right click
            handle_right_button(x, y);
        }
    }
    
    private void handle_middle_button(double x, double y) {
        mouse_state.button2_clicked = true;
        text_view.set_middle_button_dragging(true);
        
        // Check for chord
        int64 current_time = get_monotonic_time() / 1000;
        int64 elapsed = current_time - mouse_state.button1_press_time;
        
        if (mouse_state.button1_pressed && mouse_state.selection_active && 
            elapsed <= mouse_state.button2_timeout_ms) {
            // Cut chord
            execute_cut();
            return;
        }
        
        // Set timeout for middle button command execution
        schedule_middle_button_timeout(x, y);
    }
    
    private void handle_right_button(double x, double y) {
        text_view.set_right_button_dragging(true);
        
        // Check for chord
        int64 current_time = get_monotonic_time() / 1000;
        int64 elapsed = current_time - mouse_state.button1_press_time;
        
        if (mouse_state.button1_pressed && mouse_state.selection_active && 
            elapsed <= mouse_state.button2_timeout_ms) {
            // Paste chord
            execute_paste();
            return;
        } 
        else if (mouse_state.button2_clicked && text_view.get_selected_text().strip() != "") {
            // Pipe command
            execute_pipe_command("", text_view.get_selected_text());
            return;
        }
        
        // Regular right click - look up
        schedule_right_button_action(x, y);
    }
    
    private void schedule_middle_button_timeout(double x, double y) {
        // Clear middle button dragging after timeout
        Timeout.add(500, () => {
            text_view.set_middle_button_dragging(false);
            return false;
        });
        
        // Clear button2_clicked flag
        if (mouse_state.button2_timeout_id != 0) {
            Source.remove(mouse_state.button2_timeout_id);
        }
        
        mouse_state.button2_timeout_id = Timeout.add(500, () => {
            mouse_state.button2_clicked = false;
            mouse_state.button2_timeout_id = 0;
            return false;
        });
        
        // Execute command after timeout if no chord was detected
        Timeout.add(mouse_state.button2_timeout_ms + 50, () => {
            execute_middle_button_command(x, y);
            return false;
        });
    }
    
    private void schedule_right_button_action(double x, double y) {
        Timeout.add(500, () => {
            text_view.set_right_button_dragging(false);
            return false;
        });
        
        execute_right_button_action(x, y);
    }
    
    private void execute_middle_button_command(double x, double y) {
        string selection = text_view.get_selected_text();
        
        if (selection != "") {
            execute_command_internal(selection);
        } else {
            text_view.position_cursor_at_point((int)x, (int)y);
            string word = text_view.get_word_at_cursor();
            if (word != "") {
                execute_command_internal(word);
            }
        }
    }
    
    private void execute_right_button_action(double x, double y) {
        string selection = text_view.get_selected_text();
        
        if (selection != "") {
            look_up_text(selection);
        } else {
            text_view.position_cursor_at_point((int)x, (int)y);
            string word = text_view.get_word_at_cursor();
            
            if (word != "") {
                look_up_text(word);
            } else {
                string line = text_view.get_line_at_cursor();
                if (line != "" && AcmePlumber.get_instance().analyze_text(line) != PlumbingType.UNKNOWN) {
                    look_up_text(line);
                }
            }
        }
    }
    
    private void setup_drag_gestures() {
        // Middle button drag
        var middle_drag = new Gtk.GestureDrag();
        middle_drag.set_button(2);
        text_view.add_controller(middle_drag);
        
        middle_drag.drag_begin.connect((start_x, start_y) => {
            text_view.set_middle_button_dragging(true);
            text_view.position_cursor_at_point((int)start_x, (int)start_y);
            if (!text_view.has_selection) {
                text_view.start_selection();
            }
        });
        
        middle_drag.drag_update.connect((offset_x, offset_y) => {
            double start_x, start_y;
            middle_drag.get_start_point(out start_x, out start_y);
            text_view.update_selection_at_point((int)(start_x + offset_x), (int)(start_y + offset_y));
        });
        
        middle_drag.drag_end.connect((offset_x, offset_y) => {
            string selected_text = text_view.get_selected_text();
            if (selected_text != "") {
                execute_command_internal(selected_text);
            }
            text_view.set_middle_button_dragging(false);
        });
        
        // Right button drag  
        var right_drag = new Gtk.GestureDrag();
        right_drag.set_button(3);
        text_view.add_controller(right_drag);
        
        right_drag.drag_begin.connect((start_x, start_y) => {
            text_view.set_right_button_dragging(true);
            text_view.position_cursor_at_point((int)start_x, (int)start_y);
            if (!text_view.has_selection) {
                text_view.start_selection();
            }
        });
        
        right_drag.drag_update.connect((offset_x, offset_y) => {
            double start_x, start_y;
            right_drag.get_start_point(out start_x, out start_y);
            text_view.update_selection_at_point((int)(start_x + offset_x), (int)(start_y + offset_y));
        });
        
        right_drag.drag_end.connect((offset_x, offset_y) => {
            string selected_text = text_view.get_selected_text();
            if (selected_text != "") {
                look_up_text(selected_text);
            }
            text_view.set_right_button_dragging(false);
        });
    }
    
    // Simplified pipe command execution
    public void execute_pipe_command(string text, string command) {
        print("Piping text through command: %s\n", command);
        
        try {
            string[] cmd_args = {"/bin/zsh", "-c", command};
            
            var launcher = new SubprocessLauncher(SubprocessFlags.STDIN_PIPE | SubprocessFlags.STDOUT_PIPE);
            var subprocess = launcher.spawnv(cmd_args);
            
            // Send input and get output
            var stdin = subprocess.get_stdin_pipe();
            var stdout = subprocess.get_stdout_pipe();
            
            stdin.write(text.data);
            stdin.close();
            
            var data_stream = new DataInputStream(stdout);
            var output = new StringBuilder();
            string line;
            
            while ((line = data_stream.read_line()) != null) {
                output.append(line);
                output.append("\n");
            }
            
            // Replace selection with output
            if (text_view.has_selection) {
                text_view.delete_selection();
                text_view.insert_text(output.str);
            } else {
                text_view.insert_text(output.str);
            }
            
        } catch (Error e) {
            warning("Error executing pipe command: %s", e.message);
        }
    }
    
    // Public state methods
    public void set_active(bool active) {
        _is_active = active;
    }
    
    public bool is_active() {
        return _is_active;
    }
    
    // Command execution methods - simplified
    public void execute_cut() { text_view.acme_cut(); }
    public void execute_paste() { text_view.acme_paste(); }
    public void execute_snarf() { text_view.acme_snarf(); }
    
    public void execute_sort() {
        string text = text_view.get_selected_text();
        if (text == "") {
            print("No text selected to sort\n");
            return;
        }
        
        string[] lines = text.split("\n");
        Array<string> sorted_lines = new Array<string>();
        
        foreach (string line in lines) {
            sorted_lines.append_val(line);
        }
        sorted_lines.sort(strcmp);
        
        var sorted_text = new StringBuilder();
        for (int i = 0; i < sorted_lines.length; i++) {
            sorted_text.append(sorted_lines.index(i));
            if (i < sorted_lines.length - 1) {
                sorted_text.append("\n");
            }
        }
        
        text_view.delete_selection();
        text_view.insert_text(sorted_text.str);
    }
    
    public void execute_undo() {
        text_view.undo();
        if (!text_view.is_modified()) {
            dirty = false;
            dirty_indicator.set_data("dirty_state", false);
            dirty_indicator.queue_draw();
        }
        update_tag_content_based_on_state();
    }

    public void execute_redo() {
        text_view.redo();
        if (text_view.is_modified()) {
            dirty = true;
            dirty_indicator.set_data("dirty_state", true);
            dirty_indicator.queue_draw();
        }
        update_tag_content_based_on_state();
    }
    
    // File operations - simplified
    public void execute_get(string path) {
        var file = File.new_for_path(path);
        try {
            var file_info = file.query_info("standard::*", FileQueryInfoFlags.NONE);
            if (file_info.get_file_type() == FileType.DIRECTORY) {
                load_directory(path);
            } else {
                load_file(path);
            }
        } catch (Error e) {
            load_file(path); // Try as file if directory check fails
        }
    }
    
    private void load_directory(string path) {
        int view_width = get_effective_width();
        string listing = AcmeFileHandler.get_directory_listing(path, text_view.font_manager.font_desc, view_width);
        
        text_view.set_text(listing);
        set_filename(path);
        text_view.scroll_to_top();
    }
    
    private void load_file(string path) {
        try {
            var file = File.new_for_path(path);
            if (!file.query_exists()) {
                print("File does not exist: %s\n", path);
                return;
            }
            
            uint8[] contents;
            string etag_out;
            file.load_contents(null, out contents, out etag_out);
            
            string text = (string) contents;
            text_view.set_text(text);
            set_filename(path);
            text_view.scroll_to_top();
        } catch (Error e) {
            print("Error loading file: %s\n", e.message);
        }
    }
    
    public void execute_put(string path) {
        if (path == "" && filename != "Untitled") {
            path = filename;
        }
        
        try {
            string text = text_view.get_text();
            
            var file = File.new_for_path(path);
            var parent = file.get_parent();
            if (parent != null && !parent.query_exists()) {
                parent.make_directory_with_parents();
            }
            
            if (!FileUtils.set_contents(path, text)) {
                throw new IOError.FAILED("Error writing to file");
            }
            
            last_save_time = get_monotonic_time();
            modified_since_last_save = false;
            
            set_filename(path);
            
            string message = "\nFile saved: " + path + "\n";
            text_view.insert_text(message);
            
            dirty = false;
            dirty_indicator.set_data("dirty_state", false);
            dirty_indicator.queue_draw();
            file_saved();
            
            update_tag_content_based_on_state();
        } catch (Error e) {
            string error_message = "Error saving file: " + e.message;
            text_view.insert_text("\nError: " + error_message + "\n");
        }
    }
    
    public void execute_ls(string? path = null) {
        string directory_path = path ?? Environment.get_home_dir();
        
        if (directory_path == "~" || directory_path.has_prefix("~/")) {
            string home = Environment.get_home_dir();
            directory_path = (directory_path == "~") ? home : Path.build_filename(home, directory_path.substring(2));
        }
        
        int view_width = get_effective_width();
        string listing = AcmeFileHandler.get_directory_listing(directory_path, text_view.font_manager.font_desc, view_width);
        text_view.insert_text(listing);
    }

    private int get_effective_width() {
        int width = text_view.get_width();
        if (width <= 0) {
            int min_width, nat_width;
            text_view.measure(Gtk.Orientation.HORIZONTAL, -1, out min_width, out nat_width, null, null);
            width = nat_width;
        }
        return (int)Math.fmax(width, 200);
    }
    
    // Command execution system
    public void execute_command(string command) {
        execute_command_internal(command);
    }
    
    public void execute_command_internal(string command) {
        print("Executing command: %s\n", command);
        
        var context = new AcmeCommandContext.with_text_view(this);
        context.command_text = command;
        
        if (cmd_manager.execute_command(command, context)) {
            return;
        }
        
        // Execute as shell command
        execute_shell_command(command);
    }
    
    private void execute_shell_command(string command) {
        var window = get_root() as AcmeWindow;
        if (window == null) return;
        
        try {
            var errors_view = window.get_errors_view();
            if (errors_view == null) return;
            
            window.append_command_output(command, "", false);
            
            // Simple command execution
            string[] spawn_args = {"/bin/zsh", "-c", command};
            
            var launcher = new SubprocessLauncher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE);
            var subprocess = launcher.spawnv(spawn_args);
            
            var stdout = subprocess.get_stdout_pipe();
            var data_stream = new DataInputStream(stdout);
            
            string line;
            while ((line = data_stream.read_line()) != null) {
                window.append_command_output_line("", line, false);
            }
            
            subprocess.wait();
            
        } catch (Error e) {
            warning("Error executing command: %s", e.message);
            window.append_command_output("", "Error executing command: " + e.message, true);
        }
    }
    
    public void look_up_text(string text) {
        print("Looking up: %s\n", text);
        
        // Handle directory entries
        if (text.has_suffix("/")) {
            open_directory_entry(text);
            return;
        }
        
        // Check if we're in a directory view
        if (check_if_directory()) {
            if (try_open_file_in_directory(text)) {
                return;
            }
        }
        
        // Try search
        if (text.length >= 1 && (text[0] == '/' || !text.contains(" "))) {
            if (AcmeSearch.get_instance().execute_look(text, this)) {
                return;
            }
        }
        
        // Try plumber
        if (AcmePlumber.get_instance().plumb_text(text, this)) {
            return;
        }
        
        // Execute as command
        execute_command_internal(text);
    }
    
    private void open_directory_entry(string text) {
        string dir_name = text.substring(0, text.length - 1);
        string full_path = Path.is_absolute(dir_name) ? dir_name : Path.build_filename(filename, dir_name);
        open_file_in_new_view(full_path);
    }
    
    private bool try_open_file_in_directory(string text) {
        string base_text = text.contains(" ") ? text.substring(0, text.index_of(" ")) : text;
        
        // Try exact match first
        string exact_path = Path.build_filename(filename, base_text);
        if (File.new_for_path(exact_path).query_exists()) {
            open_file_in_new_view(exact_path);
            return true;
        }
        
        // Try pattern matching
        try {
            var dir = File.new_for_path(filename);
            var enumerator = dir.enumerate_children("standard::*", FileQueryInfoFlags.NONE);
            
            string[] matching_files = {};
            FileInfo info;
            while ((info = enumerator.next_file()) != null) {
                string name = info.get_name();
                if (name.has_prefix(base_text) && 
                    (name.length == base_text.length || name[base_text.length:base_text.length+1] == ".")) {
                    matching_files += Path.build_filename(filename, name);
                }
            }
            
            if (matching_files.length > 0) {
                open_file_in_new_view(matching_files[0]);
                return true;
            }
            
        } catch (Error e) {
            // Ignore errors
        }
        
        return false;
    }
    
    private void open_file_in_new_view(string filepath) {
        AcmeColumn? parent_column = null;
        Gtk.Widget? widget = this;
        
        while (widget != null && !(widget is AcmeColumn)) {
            widget = widget.get_parent();
        }
        
        if (widget != null) {
            parent_column = widget as AcmeColumn;
        }
        
        if (parent_column == null) return;
        
        try {
            var new_view = new AcmeTextView();
            parent_column.add_text_view(new_view);
            new_view.execute_get(filepath);
            
            if (check_if_directory()) {
                new_view.ensure_directory_tagline();
            }
        } catch (Error e) {
            print("Error opening file: %s\n", e.message);
        }
    }
    
    // Static initialization method
    public static void initialize_with_home_directory(AcmeTextView view) {
        string home_dir = Environment.get_home_dir();
        view.update_filename(home_dir);
        view.execute_get(home_dir);
        view.ensure_directory_tagline();
        view.text_view.scroll_to_top();
    }
    
    public void ensure_directory_tagline() {
        if (check_if_directory()) {
            var tag_text = new StringBuilder();
            
            string display_path = filename;
            if (!display_path.has_prefix("/")) {
                display_path = "/" + display_path;
            }
            tag_text.append(display_path);
            tag_text.append(" Del Snarf Get | Look ");
            
            set_tag_content(tag_text.str);
        }
    }
    
    // Accessor methods
    public string get_filename() { return filename; }
    public Gtk.Widget get_text_view() { return text_view; }
    public bool is_dirty() { return dirty; }
    public bool is_modified_since_save() { return modified_since_last_save && (last_modification_time > last_save_time); }
    
    public void update_filename(string new_filename) {
        filename = new_filename;
        dirty = false;
        dirty_indicator.set_data("dirty_state", false);
        dirty_indicator.queue_draw();
        update_tag_content_based_on_state();
    }
    
    public string get_tag_content() { return tag_content; }
    
    public void set_tag_content(string content) {
        tag_content = content;
        tag_line.set_text(content, true);
    }
    
    public void set_real_time_scrolling(bool enable) {
        auto_scroll = enable;
    }
    
    public void scroll_to_end() {
        if (auto_scroll) {
            text_view.scroll_to_end();
        }
    }
    
    public void scroll_to_line_column(int line, int column) {
        text_view.scroll_to_line_column(line, column);
    }
    
    public void set_filename(string new_filename) {
        filename = new_filename;
        dirty = false;
        dirty_indicator.set_data("dirty_state", false);
        dirty_indicator.queue_draw();
        update_tag_content_based_on_state();
    }
}