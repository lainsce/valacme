/* window.vala
 * Root window implementation
 */

public class AcmeWindow : Gtk.ApplicationWindow {
    private Gtk.Box main_box;
    private Gtk.Box root_box;
    private List<AcmeColumn> columns;
    
    public AcmeDrawingTextView main_tag_line;
    public string tag_content = "";

    public struct ColumnOperationState {
        AcmeColumn? resize_column;
        int resize_start_width;
        int resize_start_mouse_x;
        AcmeColumn? reorder_column;
        int reorder_original_index;
        
        public void reset() {
            resize_column = null;
            resize_start_width = 0;
            resize_start_mouse_x = 0;
            reorder_column = null;
            reorder_original_index = -1;
        }
    }
    private ColumnOperationState column_ops;

    public struct TextViewOperationState {
        AcmeTextView? dragging_textview;
        AcmeColumn? target_column;
        double drag_start_x;
        
        public void reset() {
            dragging_textview = null;
            target_column = null;
            drag_start_x = 0;
        }
    }
    private TextViewOperationState textview_ops;
    
    // Command manager and errors view
    private AcmeCommandManager cmd_manager;
    private AcmeTextView? errors_view = null;
    
    public AcmeWindow (Gtk.Application app) {
        Object (
            application: app,
            title: "Valacme",
            default_width: 1215,
            default_height: 810
        );
        
        columns = new List<AcmeColumn> ();
        cmd_manager = AcmeCommandManager.get_instance();
        column_ops = ColumnOperationState();
        textview_ops = TextViewOperationState();
        
        setup_ui ();
    }
    
    private void setup_ui () {
        root_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        this.set_child (root_box);
        
        // Create main tag bar
        var main_tag_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);
        main_tag_box.add_css_class ("acme-main-tag");
        
        main_tag_line = new AcmeDrawingTextView(false);
        main_tag_line.set_hexpand(true);
        main_tag_line.set_size_request(-1, 16);

        // Style the tag line
        Gdk.RGBA tag_bg = Gdk.RGBA();
        tag_bg.parse("#E9FFFE");
        main_tag_line.set_background_color(tag_bg);
        
        Gdk.RGBA tag_bg_sel = Gdk.RGBA();
        tag_bg_sel.parse("#9eeeee");
        main_tag_line.set_selection_color(tag_bg_sel);
        
        main_tag_box.append (main_tag_line);
        setup_tag_mouse_handling(main_tag_line);
        setup_initial_tag();
        
        root_box.append (main_tag_box);
        
        // Create columns container
        main_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        main_box.vexpand = true;
        root_box.append (main_box);
        
        // Add keyboard controller
        var key_controller = new Gtk.EventControllerKey();
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            return false; // No global shortcuts for now
        });
        main_box.add_controller(key_controller);
        
        initialize_authentic_layout();
    }
    
    public void setup_initial_tag() {
        tag_content = "Newcol Kill Putall Dump Exit ";
        main_tag_line.set_text(tag_content, true);
    }
    
    public void setup_tag_mouse_handling(AcmeDrawingTextView tag_view) {
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
                    execute_main_tag_command(word);
                }
            }
        });
    }
    
    private void execute_main_tag_command(string word) {
        switch(word) {
            case "Newcol": on_newcol_clicked(); break;
            case "Kill": on_kill_clicked(); break;
            case "Putall": on_putall_clicked(); break;
            case "Dump": on_dump_clicked(); break;
            case "Load": on_load_clicked(); break;
            case "Exit": on_exit_clicked(); break;
        }
    }
    
    // Initialize with authentic Acme layout
    private void initialize_authentic_layout() {
        // Left column (empty)
        var left_column = new AcmeColumn();
        add_column_to_ui(left_column);
        
        // Right column with home directory
        var right_column = new AcmeColumn();
        add_column_to_ui(right_column);
        
        var text_view = new AcmeTextView();
        right_column.add_text_view(text_view);
        AcmeTextView.initialize_with_home_directory(text_view);
        text_view.ensure_directory_tagline();
        
        // Set column widths
        int total_width = 1215;
        int left_col_width = total_width - 485;
        
        right_column.set_size_request(485, -1);
        left_column.set_size_request(left_col_width, -1);
        
        update_column_borders();
    }
    
    private void add_column_to_ui(AcmeColumn column) {
        main_box.append(column);
        columns.append(column);
        
        column.close_requested.connect(() => {
            handle_column_close(column);
        });
    }
    
    private void update_column_borders() {
        var theme_manager = AcmeThemeManager.get_instance();
        uint column_count = columns.length();
        
        for (int i = 0; i < column_count; i++) {
            var column = columns.nth_data(i);
            bool is_rightmost = (i == column_count - 1);
            theme_manager.apply_column_border_style(column, is_rightmost);
        }
    }
    
    public AcmeColumn? get_last_column() {
        return columns.length() > 0 ? columns.nth_data(columns.length() - 1) : null;
    }

    // Command callbacks - simplified
    public void on_newcol_clicked () { add_column(); }
    
    public void on_putall_clicked () {
        bool any_saved = false;
        
        foreach (var column in columns) {
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView) child;
                    
                    if (text_view.is_dirty() && text_view.get_filename() != "Untitled") {
                        var context = new AcmeCommandContext.with_text_view(text_view);
                        cmd_manager.execute_command("Put", context);
                        any_saved = true;
                    }
                }
                child = child.get_next_sibling();
            }
        }
        
        if (!any_saved) {
            print("No modified files to save\n");
        }
    }
    
    public void on_kill_clicked () {
        // Simplified kill dialog
        var dialog_window = new Gtk.Window();
        dialog_window.set_title("Kill Command");
        dialog_window.set_modal(true);
        dialog_window.set_transient_for(this);
        dialog_window.set_default_size(300, -1);
        
        var main_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);
        main_box.margin_start = 12;
        main_box.margin_end = 12;
        main_box.margin_top = 12;
        main_box.margin_bottom = 12;
        dialog_window.set_child(main_box);
        
        var grid = new Gtk.Grid();
        grid.row_spacing = 6;
        grid.column_spacing = 6;
        main_box.append(grid);
        
        var pid_label = new Gtk.Label("Process ID:");
        pid_label.halign = Gtk.Align.START;
        grid.attach(pid_label, 0, 0, 1, 1);
        
        var pid_entry = new Gtk.Entry();
        pid_entry.hexpand = true;
        grid.attach(pid_entry, 1, 0, 1, 1);
        
        var button_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
        button_box.homogeneous = true;
        button_box.margin_top = 12;
        main_box.append(button_box);
        
        var cancel_button = new Gtk.Button.with_label("Cancel");
        var kill_button = new Gtk.Button.with_label("Kill");
        kill_button.add_css_class("destructive-action");
        
        button_box.append(cancel_button);
        button_box.append(kill_button);
        
        cancel_button.clicked.connect(() => { dialog_window.destroy(); });
        kill_button.clicked.connect(() => {
            string pid_text = pid_entry.get_text();
            if (pid_text != "") {
                execute_kill_command(int.parse(pid_text));
            }
            dialog_window.destroy();
        });
        
        dialog_window.present();
    }
    
    private void execute_kill_command(int pid) {
        try {
            var subprocess = new Subprocess(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE, "kill", pid.to_string());
            subprocess.wait_async.begin(null, (obj, res) => {
                try {
                    subprocess.wait_async.end(res);
                    print("Process %d killed\n", pid);
                } catch (Error e) {
                    warning("Error killing process %d: %s", pid, e.message);
                }
            });
        } catch (Error e) {
            warning("Error starting kill command: %s", e.message);
        }
    }
    
    // Simplified dump/load operations
    public void on_dump_clicked() {
        try {
            string home_dir = Environment.get_home_dir();
            string save_dir = Path.build_filename(home_dir, ".local", "share", "acme-vala");
            
            var dir = File.new_for_path(save_dir);
            if (!dir.query_exists()) {
                dir.make_directory_with_parents();
            }
            
            string csv_path = Path.build_filename(save_dir, "acme_dump.csv");
            save_state_to_csv(csv_path);
            
            print("Editor state dumped to %s\n", csv_path);
        } catch (Error e) {
            warning("Error dumping editor state: %s", e.message);
        }
    }
    
    private void save_state_to_csv(string csv_path) throws Error {
        var file = File.new_for_path(csv_path);
        var stream = file.replace(null, false, FileCreateFlags.NONE);
        var data_stream = new DataOutputStream(stream);
        
        data_stream.put_string("column_index,window_index,filename,cursor_line,cursor_col,selection_start_line,selection_start_col,selection_end_line,selection_end_col,has_selection,tag_content\n");
        
        for (int col_idx = 0; col_idx < columns.length(); col_idx++) {
            var column = columns.nth_data(col_idx);
            save_column_state_to_csv(data_stream, col_idx, column);
        }
    }
    
    private void save_column_state_to_csv(DataOutputStream stream, int col_idx, AcmeColumn column) throws Error {
        var window_index = 0;
        var content_box = column.get_content_box();
        var child = content_box.get_first_child();
        
        while (child != null) {
            if (child is AcmeTextView) {
                var text_view = (AcmeTextView)child;
                save_textview_state_to_csv(stream, col_idx, window_index, text_view);
                window_index++;
            }
            child = child.get_next_sibling();
        }
        
        // Save column tag
        stream.put_string("%d,%d,%s,%d,%d,%d,%d,%d,%d,%s,%s\n".printf(
            col_idx, -1, "Column", 0, 0, 0, 0, 0, 0, "false", column.get_tag_content()
        ));
    }
    
    private void save_textview_state_to_csv(DataOutputStream stream, int col_idx, int win_idx, AcmeTextView text_view) throws Error {
        var tv = text_view.text_view;
        
        stream.put_string("%d,%d,%s,%d,%d,%d,%d,%d,%d,%s,%s\n".printf(
            col_idx, win_idx, text_view.get_filename(),
            tv.cursor_line, tv.cursor_col,
            tv.selection_start_line, tv.selection_start_col,
            tv.selection_end_line, tv.selection_end_col,
            tv.has_selection ? "true" : "false",
            text_view.get_tag_content()
        ));
    }
    
    public void on_load_clicked() {
        try {
            string home_dir = Environment.get_home_dir();
            string csv_path = Path.build_filename(home_dir, ".local", "share", "acme-vala", "acme_dump.csv");
            
            var file = File.new_for_path(csv_path);
            if (!file.query_exists()) {
                warning("Dump file does not exist: %s", csv_path);
                return;
            }
            
            load_state_from_csv(csv_path);
            print("Editor state loaded from %s\n", csv_path);
        } catch (Error e) {
            warning("Error loading editor state: %s", e.message);
        }
    }
    
    private void load_state_from_csv(string csv_path) throws Error {
        // Clear current state
        clear_current_state();
        
        uint8[] content_data;
        string etag_out;
        File.new_for_path(csv_path).load_contents(null, out content_data, out etag_out);
        
        string contents = (string)content_data;
        string[] lines = contents.split("\n");
        
        if (lines.length < 2) {
            warning("Invalid dump file format");
            return;
        }
        
        var column_dict = new HashTable<int, AcmeColumn>(direct_hash, direct_equal);
        column_dict.insert(0, columns.nth_data(0));
        
        // Process each line
        for (int i = 1; i < lines.length; i++) {
            string line = lines[i].strip();
            if (line == "") continue;
            
            string[] parts = line.split(",", 11);
            if (parts.length < 11) continue;
            
            process_csv_line(parts, column_dict);
        }
    }
    
    private void clear_current_state() {
        while (columns.length() > 1) {
            var column = columns.nth_data(1);
            main_box.remove(column);
            columns.remove(column);
        }
        
        var first_column = columns.nth_data(0);
        var content_box = first_column.get_content_box();
        var child = content_box.get_first_child();
        while (child != null) {
            var next_child = child.get_next_sibling();
            content_box.remove(child);
            child = next_child;
        }
    }
    
    private void process_csv_line(string[] parts, HashTable<int, AcmeColumn> column_dict) {
        int col_idx = int.parse(parts[0]);
        int win_idx = int.parse(parts[1]);
        string filename = parts[2];
        string tag_content = parts[10];
        
        if (win_idx == -1) {
            // Column tag entry
            if (column_dict.contains(col_idx)) {
                column_dict.get(col_idx).set_tag_content(tag_content);
            }
            return;
        }
        
        // Get or create column
        AcmeColumn column;
        if (column_dict.contains(col_idx)) {
            column = column_dict.get(col_idx);
        } else {
            column = new AcmeColumn();
            add_column_to_ui(column);
            column_dict.insert(col_idx, column);
        }
        
        // Create text view and restore state
        var text_view = new AcmeTextView();
        column.add_text_view(text_view);
        
        if (filename != "Untitled") {
            text_view.execute_get(filename);
        }
        
        // Restore cursor and selection state
        restore_textview_state(text_view, parts);
        text_view.set_tag_content(tag_content);
        text_view.text_view.ensure_cursor_visible();
        text_view.text_view.queue_draw();
    }
    
    private void restore_textview_state(AcmeTextView text_view, string[] parts) {
        var tv = text_view.text_view;
        
        tv.cursor_line = int.parse(parts[3]);
        tv.cursor_col = int.parse(parts[4]);
        
        bool has_selection = parts[9] == "true";
        if (has_selection) {
            tv.has_selection = true;
            tv.selection_start_line = int.parse(parts[5]);
            tv.selection_start_col = int.parse(parts[6]);
            tv.selection_end_line = int.parse(parts[7]);
            tv.selection_end_col = int.parse(parts[8]);
        } else {
            tv.has_selection = false;
        }
    }
    
    public void on_exit_clicked() {
        if (has_unsaved_changes()) {
            // Could show a dialog here, but for simplicity just exit
        }
        this.close();
    }
    
    public void update_all_fonts(string font_name) {
        main_tag_line.set_font(font_name);
        
        foreach (var column in columns) {
            column.tag_line.set_font(font_name);
            
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView)child;
                    text_view.update_font(font_name);
                }
                child = child.get_next_sibling();
            }
        }
    }
    
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
        add_column_to_ui(column);
        
        var text_view = new AcmeTextView();
        column.add_text_view(text_view);
        
        update_column_borders();
    }
    
    private void handle_column_close(AcmeColumn column) {
        if (columns.length() > 1) {
            // Move text views to other columns
            move_textviews_from_closing_column(column);
            
            main_box.remove(column);
            columns.remove(column);
            update_column_borders();
        } else {
            warning("Cannot close the last column");
        }
    }
    
    private void move_textviews_from_closing_column(AcmeColumn column) {
        var content_box = column.get_content_box();
        var child = content_box.get_first_child();
        
        while (child != null) {
            if (child is AcmeTextView) {
                var text_view = (AcmeTextView)child;
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
    }
    
    // Column operation handlers - simplified
    public void begin_column_resize(AcmeColumn column, int x, int y) {
        column_ops.resize_column = column;
        column_ops.resize_start_width = column.get_width();
        
        var surface = get_surface();
        if (surface != null) {
            var seat = display.get_default_seat();
            if (seat != null) {
                var pointer = seat.get_pointer();
                double mouse_x, mouse_y;
                surface.get_device_position(pointer, out mouse_x, out mouse_y, null);
                column_ops.resize_start_mouse_x = (int)mouse_x;
            }
        }
        
        var cursor = new Gdk.Cursor.from_name("resize", null);
        surface?.set_cursor(cursor);
    }

    public void update_column_resize(AcmeColumn column, int offset_x) {
        if (column_ops.resize_column != column) return;
        
        var surface = get_surface();
        if (surface != null) {
            var seat = display.get_default_seat();
            if (seat != null) {
                var pointer = seat.get_pointer();
                double current_mouse_x, current_mouse_y;
                surface.get_device_position(pointer, out current_mouse_x, out current_mouse_y, null);
                
                int delta = (int)(current_mouse_x - column_ops.resize_start_mouse_x);
                int new_width = (int)Math.fmax(100, column_ops.resize_start_width - delta);
                
                column_ops.resize_column.set_size_request(new_width, -1);
            }
        }
    }

    public void end_column_resize(AcmeColumn column) {
        if (column_ops.resize_column != column) return;
        
        get_surface()?.set_cursor(null);
        column_ops.reset();
    }
    
    public void begin_column_reorder(AcmeColumn column, int x, int y) {
        column_ops.reorder_column = column;
        
        for (int i = 0; i < columns.length(); i++) {
            if (columns.nth_data(i) == column) {
                column_ops.reorder_original_index = i;
                break;
            }
        }
        
        var cursor = new Gdk.Cursor.from_name("grab", null);
        get_surface()?.set_cursor(cursor);
    }

    public void end_column_reorder(AcmeColumn column, int offset_x) {
        if (column_ops.reorder_column != column || column_ops.reorder_original_index < 0) return;
        
        int target_index = column_ops.reorder_original_index;
        
        if (offset_x > 20 && column_ops.reorder_original_index < columns.length() - 1) {
            target_index = column_ops.reorder_original_index + 1;
        } else if (offset_x < -20 && column_ops.reorder_original_index > 0) {
            target_index = column_ops.reorder_original_index - 1;
        }
        
        if (target_index != column_ops.reorder_original_index) {
            reorder_column(column, target_index);
            update_column_borders();
        }
        
        get_surface()?.set_cursor(null);
        column_ops.reset();
    }
    
    private void reorder_column(AcmeColumn moving_column, int target_index) {
        main_box.remove(moving_column);
        columns.remove(moving_column);
        
        if (target_index >= columns.length()) {
            main_box.append(moving_column);
            columns.append(moving_column);
        } else {
            if (target_index == 0) {
                main_box.prepend(moving_column);
            } else {
                main_box.append(moving_column);
                var before_col = columns.nth_data(target_index - 1);
                main_box.reorder_child_after(moving_column, before_col);
            }
            columns.insert(moving_column, target_index);
        }
    }
    
    // TextView operation handlers - simplified
    public void begin_textview_drag(AcmeTextView textview) {
        textview_ops.dragging_textview = textview;
        
        Graphene.Point point = {};
        bool success = textview.compute_point(this, Graphene.Point.zero(), out point);
        textview_ops.drag_start_x = success ? point.x : 0;
    }

    public void update_textview_drag(AcmeTextView textview, int offset_x, int offset_y) {
        if (textview_ops.dragging_textview != textview) return;

        double current_x = textview_ops.drag_start_x + offset_x;
        textview_ops.target_column = find_column_at_x(current_x);
    }
    
    private AcmeColumn? find_column_at_x(double x) {
        foreach (var column in columns) {
            int col_width = column.get_width();
            
            Graphene.Point point = {};
            column.compute_point(this, Graphene.Point.zero(), out point);
            double col_x = point.x;
            
            if (x >= col_x && x < col_x + col_width) {
                return column;
            }
        }
        return null;
    }

    public void end_textview_drag(AcmeTextView textview) {
        if (textview_ops.dragging_textview != textview) return;
        
        if (textview_ops.target_column != null) {
            move_textview_to_column(textview, textview_ops.target_column);
        }
        
        textview_ops.reset();
    }
    
    private void move_textview_to_column(AcmeTextView textview, AcmeColumn target_column) {
        Gtk.Widget? parent = textview;
        while (parent != null && !(parent is AcmeColumn)) {
            parent = parent.get_parent();
        }
        
        if (parent != null && parent != target_column) {
            var source_column = (AcmeColumn)parent;
            source_column.get_content_box().remove(textview);
            target_column.add_text_view(textview);
        }
    }
    
    // Errors view management - simplified
    public AcmeTextView get_errors_view() {
        if (errors_view != null && errors_view.get_parent() != null) {
            errors_view.set_real_time_scrolling(true);
            position_cursor_at_end(errors_view);
            return errors_view;
        }
        
        // Try to find existing +Errors view
        errors_view = find_existing_errors_view();
        if (errors_view != null) {
            errors_view.set_real_time_scrolling(true);
            position_cursor_at_end(errors_view);
            return errors_view;
        }
        
        // Create new +Errors view
        var last_column = get_last_column();
        errors_view = new AcmeTextView();
        errors_view.update_filename("+Errors");
        errors_view.set_real_time_scrolling(true);
        
        last_column.add_text_view(errors_view);
        return errors_view;
    }
    
    private AcmeTextView? find_existing_errors_view() {
        foreach (var column in columns) {
            var content_box = column.get_content_box();
            var child = content_box.get_first_child();
            
            while (child != null) {
                if (child is AcmeTextView) {
                    var text_view = (AcmeTextView)child;
                    if (text_view.get_filename() == "+Errors") {
                        return text_view;
                    }
                }
                child = child.get_next_sibling();
            }
        }
        return null;
    }
    
    private void position_cursor_at_end(AcmeTextView errors_view) {
        var tv = errors_view.text_view;
        tv.cursor_line = tv.line_count - 1;
        tv.cursor_col = tv.lines[tv.line_count - 1].length;
    }
    
    public void append_command_output(string command, string output, bool is_error = false) {
        var errors = get_errors_view();
        if (errors == null) return;
        
        var text_view = errors.text_view;
        var formatted_text = new StringBuilder();
        
        if (text_view.line_count > 1 && text_view.lines[text_view.line_count - 1].length > 0) {
            formatted_text.append("\n");
        }
        
        if (command != "") {
            if (!command.has_prefix("$ ")) {
                formatted_text.append("$ ");
            }
            formatted_text.append(command);
            formatted_text.append("\n");
        }
        
        if (output != "") {
            formatted_text.append(output);
        }
        
        text_view.insert_text(formatted_text.str);
        text_view.scroll_to_end();
    }
    
    public void append_command_output_line(string command, string line, bool is_error) {
        if (line == "" || line == command || line == "$ " + command) return;
        
        var errors = get_errors_view();
        if (errors == null) return;
        
        errors.text_view.insert_text(line + "\n");
        errors.text_view.scroll_to_end();
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
    
    public void move_text_view_to_column(AcmeTextView view, int column_index) {
        if (column_index < 0 || column_index >= columns.length()) {
            warning("Invalid column index: %d", column_index);
            return;
        }
        
        var target_column = columns.nth_data(column_index);
        var current_parent = view.get_parent();
        
        if (current_parent != null) {
            ((Gtk.Box)current_parent).remove(view);
        }
        
        target_column.add_text_view(view);
    }
    
    public void split_text_view(AcmeTextView view) {
        var new_column = new AcmeColumn();
        add_column_to_ui(new_column);
        
        var current_parent = view.get_parent();
        if (current_parent != null) {
            ((Gtk.Box)current_parent).remove(view);
        }
        
        new_column.add_text_view(view);
    }
}