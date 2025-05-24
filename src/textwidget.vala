/* acme_drawing_textview.vala
 * Custom text view implementation
 */

/* Text content management - separate from UI concerns */
public class AcmeTextBuffer : Object {
    public string[] lines;
    public int line_count;
    
    public signal void text_changed();
    
    public AcmeTextBuffer() {
        lines = new string[1];
        lines[0] = "";
        line_count = 1;
    }
    
    public string get_text() {
        var sb = new StringBuilder();
        for (int i = 0; i < line_count; i++) {
            sb.append(lines[i]);
            if (i < line_count - 1) sb.append("\n");
        }
        return sb.str;
    }
    
    public void set_text(string text) {
        string[] new_lines = text.split("\n");
        line_count = new_lines.length;
        
        if (line_count > lines.length) {
            lines = new string[line_count * 2];
        }
        
        for (int i = 0; i < line_count; i++) {
            lines[i] = new_lines[i];
        }
        
        text_changed();
    }
    
    public void insert_text_at(int line, int col, string text) {
        if (text.contains("\n")) {
            insert_multiline_text(line, col, text);
        } else {
            insert_single_line_text(line, col, text);
        }
        text_changed();
    }
    
    public void insert_single_line_text(int line, int col, string text) {
        string current_line = lines[line];
        lines[line] = current_line.substring(0, col) + text + current_line.substring(col);
    }
    
    public void insert_multiline_text(int line, int col, string text) {
        string[] new_lines = text.split("\n");
        string current_line = lines[line];
        string first_part = current_line.substring(0, col);
        string last_part = current_line.substring(col);
        
        // Update first line
        lines[line] = first_part + new_lines[0];
        
        // Insert new lines
        int new_line_count = new_lines.length - 1;
        if (line_count + new_line_count >= lines.length) {
            expand_buffer(line_count + new_line_count + 10);
        }
        
        // Shift existing lines down
        for (int i = line_count + new_line_count - 1; i > line + new_line_count; i--) {
            lines[i] = lines[i - new_line_count];
        }
        
        // Insert middle lines
        for (int i = 1; i < new_lines.length; i++) {
            lines[line + i] = (i == new_lines.length - 1) ? 
                new_lines[i] + last_part : new_lines[i];
        }
        
        line_count += new_line_count;
    }
    
    public void delete_range(int start_line, int start_col, int end_line, int end_col) {
        if (start_line == end_line) {
            delete_within_line(start_line, start_col, end_col);
        } else {
            delete_across_lines(start_line, start_col, end_line, end_col);
        }
        text_changed();
    }
    
    public void delete_within_line(int line, int start_col, int end_col) {
        string current_line = lines[line];
        lines[line] = current_line.substring(0, start_col) + current_line.substring(end_col);
    }
    
    public void delete_across_lines(int start_line, int start_col, int end_line, int end_col) {
        string first_line = lines[start_line];
        string last_line = lines[end_line];
        
        // Merge first and last line parts
        lines[start_line] = first_line.substring(0, start_col) + last_line.substring(end_col);
        
        // Remove lines in between
        int lines_to_remove = end_line - start_line;
        for (int i = start_line + 1; i < line_count - lines_to_remove; i++) {
            lines[i] = lines[i + lines_to_remove];
        }
        line_count -= lines_to_remove;
    }
    
    public void expand_buffer(int new_size) {
        string[] new_lines = new string[new_size * 2];
        for (int i = 0; i < line_count; i++) {
            new_lines[i] = lines[i];
        }
        lines = new_lines;
    }
}

/* Cursor and selection state - separate concern */  
public class AcmeTextCursor : Object {
    public int line;
    public int col;
    public bool has_selection;
    public int selection_start_line;
    public int selection_start_col;
    public int selection_end_line;
    public int selection_end_col;
    
    public signal void cursor_moved();
    public signal void selection_changed();
    
    public AcmeTextCursor() {
        line = 0;
        col = 0;
        has_selection = false;
    }
    
    public void move_to(int new_line, int new_col) {
        line = new_line;
        col = new_col;
        cursor_moved();
    }
    
    public void start_selection() {
        has_selection = true;
        selection_start_line = line;
        selection_start_col = col;
        selection_end_line = line;
        selection_end_col = col;
        selection_changed();
    }
    
    public void update_selection(int new_line, int new_col) {
        if (has_selection) {
            selection_end_line = new_line;
            selection_end_col = new_col;
            selection_changed();
        }
    }
    
    public void clear_selection() {
        if (has_selection) {
            has_selection = false;
            selection_changed();
        }
    }
    
    public string get_selected_text(AcmeTextBuffer buffer) {
        if (!has_selection) return "";
        
        if (selection_start_line == selection_end_line) {
            string line_text = buffer.lines[selection_start_line];
            return line_text.substring(selection_start_col, selection_end_col - selection_start_col);
        }
        
        var sb = new StringBuilder();
        
        // First line
        string first_line = buffer.lines[selection_start_line];
        sb.append(first_line.substring(selection_start_col));
        sb.append("\n");
        
        // Middle lines
        for (int i = selection_start_line + 1; i < selection_end_line; i++) {
            sb.append(buffer.lines[i]);
            sb.append("\n");
        }
        
        // Last line
        string last_line = buffer.lines[selection_end_line];
        sb.append(last_line.substring(0, selection_end_col));
        
        return sb.str;
    }
}

/* Font and rendering metrics - separate concern */
public class AcmeFontManager : Object {
    public Pango.FontDescription font_desc;
    public int font_height;
    public int char_width;
    public Gee.HashMap<unichar, int>? char_width_cache;
    
    public AcmeFontManager() {
        font_desc = new Pango.FontDescription();
        font_desc.set_family("Go");
        font_desc.set_size((int)(11 * Pango.SCALE));
        calculate_font_metrics();
    }
    
    public void set_font(string font_name) {
        font_desc = Pango.FontDescription.from_string(font_name);
        calculate_font_metrics();
    }
    
    public void calculate_font_metrics() {
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
        var cr = new Cairo.Context(surface);
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(font_desc);
        
        // Calculate font height
        layout.set_text("M", 1);
        int height_m;
        layout.get_pixel_size(null, out height_m);
        font_height = height_m;
        
        // Calculate average character width
        string sample_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        layout.set_text(sample_chars, -1);
        int total_width;
        layout.get_pixel_size(out total_width, null);
        char_width = total_width / sample_chars.length;
        
        cache_common_char_widths(layout);
        surface.finish();
    }
    
    public void cache_common_char_widths(Pango.Layout layout) {
        char_width_cache = new Gee.HashMap<unichar, int>();
        for (int i = 32; i <= 126; i++) {
            unichar c = (unichar)i;
            string str = c.to_string();
            layout.set_text(str, -1);
            int width;
            layout.get_pixel_size(out width, null);
            char_width_cache[c] = width;
        }
    }
    
    public int get_text_width(string text) {
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
        var cr = new Cairo.Context(surface);
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(font_desc);
        layout.set_text(text, -1);
        int width;
        layout.get_pixel_size(out width, null);
        surface.finish();
        return width;
    }
    
    public int x_to_column(string line, double x) {
        if (x <= 0) return 0;
        
        // Binary search approach
        int left = 0;
        int right = line.length;
        
        while (left < right) {
            int mid = (left + right) / 2;
            string substring = line.substring(0, mid);
            int width = get_text_width(substring);
            
            if (width < x) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        
        return left;
    }
}

/* Input handling - separate concern */
public class AcmeInputHandler : Object {  
    public weak AcmeDrawingTextView text_view;
    
    public AcmeInputHandler(AcmeDrawingTextView view) {
        text_view = view;
    }
    
    public void setup_input_handling() {
        setup_keyboard_input();
        setup_mouse_input();
        setup_scroll_input();
    }
    
    public void setup_keyboard_input() {
        var key_controller = new Gtk.EventControllerKey();
        key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        text_view.add_controller(key_controller);
        
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            bool handled = handle_key_press(keyval, state);
            text_view.ensure_cursor_visible();
            text_view.queue_draw();
            return handled;
        });
    }
    
    public void setup_mouse_input() {
        var click = new Gtk.GestureClick();
        click.set_button(1);
        text_view.add_controller(click);
        
        click.pressed.connect((n_press, x, y) => {
            text_view.position_cursor_at_point((int)x, (int)y);
            text_view.cursor.clear_selection();
            text_view.cursor.start_selection();
            text_view.grab_focus();
            text_view.queue_draw();
        });
        
        var drag = new Gtk.GestureDrag();
        text_view.add_controller(drag);
        
        drag.drag_begin.connect((start_x, start_y) => {
            text_view.position_cursor_at_point((int)start_x, (int)start_y);
            text_view.cursor.start_selection();
        });
        
        drag.drag_update.connect((offset_x, offset_y) => {
            double start_x, start_y;
            drag.get_start_point(out start_x, out start_y);
            text_view.update_selection_at_point((int)(start_x + offset_x), (int)(start_y + offset_y));
        });
    }
    
    public void setup_scroll_input() {
        var scroll = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.VERTICAL);
        text_view.add_controller(scroll);
        
        scroll.scroll.connect((dx, dy) => {
            int lines_to_scroll = (int)(dy > 0 ? 3 : -3);
            text_view.scroll_by_lines(lines_to_scroll);
            return true;
        });
    }
    
    public bool handle_key_press(uint keyval, Gdk.ModifierType state) {
        switch (keyval) {
            case Gdk.Key.Up: text_view.move_cursor_up(); return true;
            case Gdk.Key.Down: text_view.move_cursor_down(); return true;
            case Gdk.Key.Left: text_view.move_cursor_left(); return true;
            case Gdk.Key.Right: text_view.move_cursor_right(); return true;
            case Gdk.Key.Home: text_view.move_cursor_to_line_start(); return true;
            case Gdk.Key.End: text_view.move_cursor_to_line_end(); return true;
            case Gdk.Key.Page_Up: text_view.page_up(); return true;
            case Gdk.Key.Page_Down: text_view.page_down(); return true;
            case Gdk.Key.BackSpace: text_view.delete_backward(); return true;
            case Gdk.Key.Delete: text_view.delete_forward(); return true;
            case Gdk.Key.Return: case Gdk.Key.KP_Enter: text_view.insert_newline(); return true;
            case Gdk.Key.Tab: text_view.insert_text("    "); return true;
            default:
                if (keyval >= 32 && keyval <= 126) {
                    text_view.insert_text(((char)keyval).to_string());
                    return true;
                }
                return false;
        }
    }
}

/* Undo/Redo management - separate concern */
public class AcmeUndoManager : Object {
    public class TextOperation {
        public enum OpType { INSERT, DELETE }
        
        public OpType op_type;
        public string text;
        public int start_line;
        public int start_col;
        public int end_line;
        public int end_col;
        
        public TextOperation(OpType type, string content, int sline, int scol, int eline = -1, int ecol = -1) {
            op_type = type;
            text = content;
            start_line = sline;
            start_col = scol;
            end_line = (eline >= 0) ? eline : sline;
            end_col = (ecol >= 0) ? ecol : scol;
        }
    }
    
    public Gee.ArrayList<TextOperation> undo_stack;
    public Gee.ArrayList<TextOperation> redo_stack;
    public bool in_undo_operation = false;
    
    public signal void undo_stack_changed();
    public signal void redo_stack_changed();
    
    public AcmeUndoManager() {
        undo_stack = new Gee.ArrayList<TextOperation>();
        redo_stack = new Gee.ArrayList<TextOperation>();
    }
    
    public void record_insert(string text, int start_line, int start_col) {
        if (!in_undo_operation) {
            undo_stack.add(new TextOperation(TextOperation.OpType.INSERT, text, start_line, start_col));
            redo_stack.clear();
            undo_stack_changed();
            redo_stack_changed();
        }
    }
    
    public void record_delete(string text, int start_line, int start_col, int end_line, int end_col) {
        if (!in_undo_operation) {
            undo_stack.add(new TextOperation(TextOperation.OpType.DELETE, text, start_line, start_col, end_line, end_col));
            redo_stack.clear();
            undo_stack_changed();
            redo_stack_changed();
        }
    }
    
    public bool can_undo() { return undo_stack.size > 0; }
    public bool can_redo() { return redo_stack.size > 0; }
    
    public void undo(AcmeTextBuffer buffer, AcmeTextCursor cursor) {
        if (undo_stack.size == 0) return;
        
        in_undo_operation = true;
        var op = undo_stack.remove_at(undo_stack.size - 1);
        redo_stack.add(op);
        
        if (op.op_type == TextOperation.OpType.INSERT) {
            // Undo insert by deleting
            buffer.delete_range(op.start_line, op.start_col, op.end_line, op.end_col);
            cursor.move_to(op.start_line, op.start_col);
        } else {
            // Undo delete by inserting
            buffer.insert_text_at(op.start_line, op.start_col, op.text);
            cursor.move_to(op.end_line, op.end_col);
        }
        
        in_undo_operation = false;
        undo_stack_changed();
        redo_stack_changed();
    }
    
    public void redo(AcmeTextBuffer buffer, AcmeTextCursor cursor) {
        if (redo_stack.size == 0) return;
        
        in_undo_operation = true;
        var op = redo_stack.remove_at(redo_stack.size - 1);
        undo_stack.add(op);
        
        if (op.op_type == TextOperation.OpType.INSERT) {
            // Redo insert
            buffer.insert_text_at(op.start_line, op.start_col, op.text);
            cursor.move_to(op.end_line, op.end_col);
        } else {
            // Redo delete
            buffer.delete_range(op.start_line, op.start_col, op.end_line, op.end_col);
            cursor.move_to(op.start_line, op.start_col);
        }
        
        in_undo_operation = false;
        undo_stack_changed();
        redo_stack_changed();
    }
    
    public void clear() {
        undo_stack.clear();
        redo_stack.clear();
        undo_stack_changed();
        redo_stack_changed();
    }
}

/* Main text view - now much simpler, delegates to components */
public class AcmeDrawingTextView : Gtk.DrawingArea {
    // Components - single responsibility each
    public AcmeTextBuffer buffer;
    public AcmeTextCursor cursor;
    public AcmeFontManager font_manager;
    public AcmeInputHandler input_handler;
    public AcmeUndoManager undo_manager;
    
    // Visual state
    public Gdk.RGBA text_color;
    public Gdk.RGBA bg_color;
    public Gdk.RGBA selection_color;
    public Gdk.RGBA cursor_color;
    
    // Scroll and view state
    public int scroll_offset_y;
    public int visible_lines;
    public bool has_margins;
    
    // Button state for visual feedback
    public bool middle_button_dragging = false;
    public bool right_button_dragging = false;
    
    // Clipboard
    public Gdk.Clipboard clipboard;
    
    // Signals - forward from components
    public signal void text_changed();
    public signal void cursor_moved();
    public signal void selection_changed();
    public signal void undo_stack_changed();
    public signal void redo_stack_changed();
    
    public AcmeDrawingTextView(bool margins) {
        // Initialize components
        buffer = new AcmeTextBuffer();
        cursor = new AcmeTextCursor();
        font_manager = new AcmeFontManager();
        input_handler = new AcmeInputHandler(this);
        undo_manager = new AcmeUndoManager();
        
        has_margins = margins;
        scroll_offset_y = 0;
        
        // Setup colors
        text_color = Gdk.RGBA();
        text_color.parse("#000000");
        bg_color = Gdk.RGBA();
        bg_color.parse("#FFFFEA");
        selection_color = Gdk.RGBA();
        selection_color.parse("#EEEE9E");
        cursor_color = Gdk.RGBA();
        cursor_color.parse("#000000");
        
        // Get clipboard
        clipboard = Gdk.Display.get_default().get_clipboard();
        
        // Connect component signals
        buffer.text_changed.connect(() => { text_changed(); });
        cursor.cursor_moved.connect(() => { cursor_moved(); });
        cursor.selection_changed.connect(() => { selection_changed(); });
        undo_manager.undo_stack_changed.connect(() => { undo_stack_changed(); });
        undo_manager.redo_stack_changed.connect(() => { redo_stack_changed(); });
        
        // Setup UI
        set_size_request(400, 300);
        set_draw_func(draw_func);
        set_focusable(true);
        set_can_focus(true);
        set_focus_on_click(true);
        
        input_handler.setup_input_handling();
    }
    
    // Simplified drawing - delegates to components
    public void draw_func(Gtk.DrawingArea drawing_area, Cairo.Context cr, int width, int height) {
        // Fill background
        cr.set_source_rgba(bg_color.red, bg_color.green, bg_color.blue, bg_color.alpha);
        cr.rectangle(0, 0, width, height);
        cr.fill();
        
        visible_lines = height / font_manager.font_height;
        int left_margin = has_margins ? 16 : 0;
        
        draw_text_lines(cr, width, left_margin);
        draw_cursor(cr, left_margin);
    }
    
    public void draw_text_lines(Cairo.Context cr, int width, int left_margin) {
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(font_manager.font_desc);
        
        for (int i = scroll_offset_y; i < buffer.line_count && i < scroll_offset_y + visible_lines; i++) {
            int y = (i - scroll_offset_y) * font_manager.font_height;
            
            // Draw selection if this line has any
            if (cursor.has_selection && line_has_selection(i)) {
                draw_selection_for_line(cr, i, y, width, left_margin);
            }
            
            // Draw text with special coloring for button states
            draw_line_text(cr, layout, i, y, left_margin);
        }
    }
    
    public bool line_has_selection(int line) {
        if (!cursor.has_selection) return false;
        int sel_start = (int)Math.fmin(cursor.selection_start_line, cursor.selection_end_line);
        int sel_end = (int)Math.fmax(cursor.selection_start_line, cursor.selection_end_line);
        return line >= sel_start && line <= sel_end;
    }
    
    public void draw_selection_for_line(Cairo.Context cr, int line, int y, int width, int left_margin) {
        // Calculate selection bounds for this line
        int start_col, end_col;
        
        if (cursor.selection_start_line < cursor.selection_end_line || 
            (cursor.selection_start_line == cursor.selection_end_line && cursor.selection_start_col <= cursor.selection_end_col)) {
            start_col = (line == cursor.selection_start_line) ? cursor.selection_start_col : 0;
            end_col = (line == cursor.selection_end_line) ? cursor.selection_end_col : buffer.lines[line].length;
        } else {
            start_col = (line == cursor.selection_end_line) ? cursor.selection_end_col : 0;
            end_col = (line == cursor.selection_start_line) ? cursor.selection_start_col : buffer.lines[line].length;
        }
        
        // Calculate x positions
        int start_x = left_margin;
        if (start_col > 0) {
            string text_before = buffer.lines[line].substring(0, start_col);
            start_x += font_manager.get_text_width(text_before);
        }
        
        int end_x = left_margin;
        if (end_col > 0) {
            string text_before = buffer.lines[line].substring(0, end_col);
            end_x += font_manager.get_text_width(text_before);
        }
        
        // Choose color based on button state
        if (middle_button_dragging) {
            cr.set_source_rgb(1.0, 0.0, 0.0); // Red for middle button
        } else if (right_button_dragging) {
            cr.set_source_rgb(0.0, 0.8, 0.0); // Green for right button
        } else {
            cr.set_source_rgba(selection_color.red, selection_color.green, selection_color.blue, selection_color.alpha);
        }
        
        cr.rectangle(start_x, y, end_x - start_x, font_manager.font_height);
        cr.fill();
    }
    
    public void draw_line_text(Cairo.Context cr, Pango.Layout layout, int line, int y, int left_margin) {
        string line_text = buffer.lines[line];
        
        // Check if this line has special selection coloring
        bool has_colored_selection = cursor.has_selection && line_has_selection(line) && 
                                   (middle_button_dragging || right_button_dragging);
        
        if (has_colored_selection) {
            draw_colored_selection_text(cr, layout, line_text, line, y, left_margin);
        } else {
            // Normal text drawing
            cr.set_source_rgba(text_color.red, text_color.green, text_color.blue, text_color.alpha);
            layout.set_text(line_text, -1);
            cr.move_to(left_margin, y);
            Pango.cairo_show_layout(cr, layout);
        }
    }
    
    public void draw_colored_selection_text(Cairo.Context cr, Pango.Layout layout, string line_text, int line, int y, int left_margin) {
        // Calculate selection bounds
        int line_sel_start, line_sel_end;
        
        if (cursor.selection_start_line < cursor.selection_end_line || 
            (cursor.selection_start_line == cursor.selection_end_line && cursor.selection_start_col <= cursor.selection_end_col)) {
            line_sel_start = (line == cursor.selection_start_line) ? cursor.selection_start_col : 0;
            line_sel_end = (line == cursor.selection_end_line) ? cursor.selection_end_col : line_text.length;
        } else {
            line_sel_start = (line == cursor.selection_end_line) ? cursor.selection_end_col : 0;
            line_sel_end = (line == cursor.selection_start_line) ? cursor.selection_start_col : line_text.length;
        }
        
        // Draw in parts: before selection, selection, after selection
        if (line_sel_start > 0) {
            cr.set_source_rgba(text_color.red, text_color.green, text_color.blue, text_color.alpha);
            layout.set_text(line_text.substring(0, line_sel_start), -1);
            cr.move_to(left_margin, y);
            Pango.cairo_show_layout(cr, layout);
        }
        
        // Selected text in white
        if (line_sel_end > line_sel_start) {
            cr.set_source_rgb(1.0, 1.0, 1.0);
            string selected_text = line_text.substring(line_sel_start, line_sel_end - line_sel_start);
            layout.set_text(selected_text, -1);
            
            int sel_x = left_margin;
            if (line_sel_start > 0) {
                sel_x += font_manager.get_text_width(line_text.substring(0, line_sel_start));
            }
            
            cr.move_to(sel_x, y);
            Pango.cairo_show_layout(cr, layout);
        }
        
        // Text after selection
        if (line_sel_end < line_text.length) {
            cr.set_source_rgba(text_color.red, text_color.green, text_color.blue, text_color.alpha);
            layout.set_text(line_text.substring(line_sel_end), -1);
            
            int after_x = left_margin;
            if (line_sel_end > 0) {
                after_x += font_manager.get_text_width(line_text.substring(0, line_sel_end));
            }
            
            cr.move_to(after_x, y);
            Pango.cairo_show_layout(cr, layout);
        }
    }
    
    public void draw_cursor(Cairo.Context cr, int left_margin) {
        if (cursor.line < scroll_offset_y || cursor.line >= scroll_offset_y + visible_lines) return;
        
        int x = left_margin;
        if (cursor.col > 0 && cursor.line < buffer.line_count) {
            string text_before = buffer.lines[cursor.line].substring(0, cursor.col);
            x += font_manager.get_text_width(text_before);
        }
        
        int y = (cursor.line - scroll_offset_y) * font_manager.font_height;
        
        cr.set_source_rgba(cursor_color.red, cursor_color.green, cursor_color.blue, 1.0);
        cr.set_antialias(Cairo.Antialias.NONE);
        cr.set_line_width(1.0);
        
        // Acme-style cursor
        cr.rectangle(x, y, 3, 3);
        cr.fill();
        cr.move_to(x + 2, y);
        cr.line_to(x + 2, y + font_manager.font_height - 3);
        cr.stroke();
        cr.rectangle(x, y + font_manager.font_height - 3, 3, 3);
        cr.fill();
    }
    
    // Public interface - delegates to components
    public void set_text(string text, bool cursor_at_end = false) {
        buffer.set_text(text);
        if (cursor_at_end) {
            cursor.move_to(buffer.line_count - 1, buffer.lines[buffer.line_count - 1].length);
        } else {
            cursor.move_to(0, 0);
        }
        scroll_offset_y = 0;
        cursor.clear_selection();
        undo_manager.clear();
        queue_draw();
    }
    
    public string get_text() {
        return buffer.get_text();
    }
    
    public void set_font(string font_name) {
        font_manager.set_font(font_name);
        queue_draw();
    }
    
    // Movement methods - delegate to cursor
    public void move_cursor_up() {
        if (cursor.line > 0) {
            int new_col = (int)Math.fmin(cursor.col, buffer.lines[cursor.line - 1].length);
            cursor.move_to(cursor.line - 1, new_col);
            ensure_cursor_visible();
            queue_draw();
        }
    }
    
    public void move_cursor_down() {
        if (cursor.line < buffer.line_count - 1) {
            int new_col = (int)Math.fmin(cursor.col, buffer.lines[cursor.line + 1].length);
            cursor.move_to(cursor.line + 1, new_col);
            ensure_cursor_visible();
            queue_draw();
        }
    }
    
    public void move_cursor_left() {
        if (cursor.col > 0) {
            cursor.move_to(cursor.line, cursor.col - 1);
        } else if (cursor.line > 0) {
            cursor.move_to(cursor.line - 1, buffer.lines[cursor.line - 1].length);
        }
        ensure_cursor_visible();
        queue_draw();
    }
    
    public void move_cursor_right() {
        if (cursor.col < buffer.lines[cursor.line].length) {
            cursor.move_to(cursor.line, cursor.col + 1);
        } else if (cursor.line < buffer.line_count - 1) {
            cursor.move_to(cursor.line + 1, 0);
        }
        ensure_cursor_visible();
        queue_draw();
    }
    
    public void move_cursor_to_line_start() {
        cursor.move_to(cursor.line, 0);
        ensure_cursor_visible();
        queue_draw();
    }
    
    public void move_cursor_to_line_end() {
        cursor.move_to(cursor.line, buffer.lines[cursor.line].length);
        ensure_cursor_visible();
        queue_draw();
    }
    
    // Text editing - delegates to buffer and records undo
    public void insert_text(string text) {
        if (cursor.has_selection) {
            delete_selection();
        }
        
        undo_manager.record_insert(text, cursor.line, cursor.col);
        buffer.insert_text_at(cursor.line, cursor.col, text);
        
        // Update cursor position
        if (text.contains("\n")) {
            string[] lines = text.split("\n");
            cursor.move_to(cursor.line + lines.length - 1, lines[lines.length - 1].length);
        } else {
            cursor.move_to(cursor.line, cursor.col + text.length);
        }
        
        ensure_cursor_visible();
        queue_draw();
    }
    
    public void insert_newline() {
        insert_text("\n");
    }
    
    public void delete_backward() {
        if (cursor.has_selection) {
            delete_selection();
            return;
        }
        
        if (cursor.col > 0) {
            string deleted = buffer.lines[cursor.line].substring(cursor.col - 1, 1);
            undo_manager.record_delete(deleted, cursor.line, cursor.col - 1, cursor.line, cursor.col);
            buffer.delete_range(cursor.line, cursor.col - 1, cursor.line, cursor.col);
            cursor.move_to(cursor.line, cursor.col - 1);
        } else if (cursor.line > 0) {
            undo_manager.record_delete("\n", cursor.line - 1, buffer.lines[cursor.line - 1].length, cursor.line, 0);
            int prev_line_len = buffer.lines[cursor.line - 1].length;
            buffer.delete_range(cursor.line - 1, prev_line_len, cursor.line, 0);
            cursor.move_to(cursor.line - 1, prev_line_len);
        }
        
        ensure_cursor_visible();
        queue_draw();
    }
    
    public void delete_forward() {
        if (cursor.has_selection) {
            delete_selection();
            return;
        }
        
        if (cursor.col < buffer.lines[cursor.line].length) {
            string deleted = buffer.lines[cursor.line].substring(cursor.col, 1);
            undo_manager.record_delete(deleted, cursor.line, cursor.col, cursor.line, cursor.col + 1);
            buffer.delete_range(cursor.line, cursor.col, cursor.line, cursor.col + 1);
        } else if (cursor.line < buffer.line_count - 1) {
            undo_manager.record_delete("\n", cursor.line, cursor.col, cursor.line + 1, 0);
            buffer.delete_range(cursor.line, cursor.col, cursor.line + 1, 0);
        }
        
        queue_draw();
    }
    
    public void delete_selection() {
        if (!cursor.has_selection) return;
        
        string deleted_text = cursor.get_selected_text(buffer);
        undo_manager.record_delete(deleted_text, cursor.selection_start_line, cursor.selection_start_col, 
                                  cursor.selection_end_line, cursor.selection_end_col);
        
        buffer.delete_range(cursor.selection_start_line, cursor.selection_start_col, 
                          cursor.selection_end_line, cursor.selection_end_col);
        
        cursor.move_to(cursor.selection_start_line, cursor.selection_start_col);
        cursor.clear_selection();
        
        ensure_cursor_visible();
        queue_draw();
    }
    
    // Undo/Redo - delegate to undo manager
    public void undo() {
        undo_manager.undo(buffer, cursor);
        ensure_cursor_visible();
        queue_draw();
    }
    
    public void redo() {
        undo_manager.redo(buffer, cursor);
        ensure_cursor_visible();
        queue_draw();
    }
    
    public bool can_undo() { return undo_manager.can_undo(); }
    public bool can_redo() { return undo_manager.can_redo(); }
    public bool is_modified() { return undo_manager.can_undo(); }
    
    // Selection methods
    public void start_selection() {
        cursor.start_selection();
        queue_draw();
    }
    
    public void clear_selection() {
        cursor.clear_selection();
        queue_draw();
    }
    
    public string get_selected_text() {
        return cursor.get_selected_text(buffer);
    }
    
    // Position methods
    public void position_cursor_at_point(int x, int y) {
        int line = scroll_offset_y + (y / font_manager.font_height);
        line = (int)Math.fmax(0, Math.fmin(line, buffer.line_count - 1));
        
        int adjusted_x = has_margins ? (int)Math.fmax(0, x - 17) : x;
        int col = font_manager.x_to_column(buffer.lines[line], adjusted_x);
        col = (int)Math.fmin(col, buffer.lines[line].length);
        
        cursor.move_to(line, col);
        queue_draw();
    }
    
    public void update_selection_at_point(int x, int y) {
        int line = scroll_offset_y + (y / font_manager.font_height);
        line = (int)Math.fmax(0, Math.fmin(line, buffer.line_count - 1));
        
        int adjusted_x = has_margins ? (int)Math.fmax(0, x - 17) : x;
        int col = font_manager.x_to_column(buffer.lines[line], adjusted_x);
        col = (int)Math.fmin(col, buffer.lines[line].length);
        
        cursor.move_to(line, col);
        cursor.update_selection(line, col);
        queue_draw();
    }
    
    // Scroll methods
    public void scroll_by_lines(int num_lines) {
        scroll_offset_y += num_lines;
        scroll_offset_y = (int)Math.fmax(0, Math.fmin(scroll_offset_y, buffer.line_count - visible_lines));
        queue_draw();
    }
    
    public void scroll_to_top() {
        scroll_offset_y = 0;
        queue_draw();
    }
    
    public void scroll_to_end() {
        if (buffer.line_count > visible_lines) {
            scroll_offset_y = buffer.line_count - visible_lines;
        } else {
            scroll_offset_y = 0;
        }
        queue_draw();
    }
    
    public void scroll_to_line_column(int line, int column) {
        line = (int)Math.fmax(0, Math.fmin(line, buffer.line_count - 1));
        column = (int)Math.fmax(0, Math.fmin(column, buffer.lines[line].length));
        
        cursor.move_to(line, column);
        ensure_cursor_visible();
        queue_draw();
    }
    
    public void ensure_cursor_visible() {
        if (cursor.line < scroll_offset_y) {
            scroll_offset_y = cursor.line;
        } else if (cursor.line >= scroll_offset_y + visible_lines) {
            scroll_offset_y = cursor.line - visible_lines + 1;
        }
    }
    
    public void page_up() {
        int move_lines = (int)Math.fmax(1, visible_lines - 1);
        if (cursor.line >= move_lines) {
            cursor.move_to(cursor.line - move_lines, (int)Math.fmin(cursor.col, buffer.lines[cursor.line - move_lines].length));
        } else {
            cursor.move_to(0, (int)Math.fmin(cursor.col, buffer.lines[0].length));
        }
        
        scroll_offset_y -= move_lines;
        scroll_offset_y = (int)Math.fmax(0, scroll_offset_y);
        
        queue_draw();
    }
    
    public void page_down() {
        int move_lines = (int)Math.fmax(1, visible_lines - 1);
        if (cursor.line + move_lines < buffer.line_count) {
            cursor.move_to(cursor.line + move_lines, (int)Math.fmin(cursor.col, buffer.lines[cursor.line + move_lines].length));
        } else {
            cursor.move_to(buffer.line_count - 1, (int)Math.fmin(cursor.col, buffer.lines[buffer.line_count - 1].length));
        }
        
        scroll_offset_y += move_lines;
        scroll_offset_y = (int)Math.fmin(scroll_offset_y, (int)Math.fmax(0, buffer.line_count - visible_lines));
        
        queue_draw();
    }
    
    // Utility methods
    public string get_word_at_cursor() {
        if (cursor.line >= buffer.line_count) return "";
        
        string line = buffer.lines[cursor.line];
        if (cursor.col >= line.length) return "";
        
        int start = cursor.col;
        while (start > 0 && is_word_char(line[start - 1])) {
            start--;
        }
        
        int end = cursor.col;
        while (end < line.length && is_word_char(line[end])) {
            end++;
        }
        
        if (start == end) return "";
        return line.substring(start, end - start);
    }
    
    public string get_line_at_cursor() {
        if (cursor.line >= buffer.line_count) return "";
        return buffer.lines[cursor.line];
    }
    
    public bool is_word_char(char c) {
        return c.isalnum() || c == '_';
    }
    
    // Clipboard operations
    public void acme_cut() {
        if (cursor.has_selection) {
            copy_selection();
            delete_selection();
        }
    }
    
    public void acme_paste() {
        clipboard.read_text_async.begin(null, (obj, res) => {
            try {
                string? text = clipboard.read_text_async.end(res);
                if (text != null && text != "") {
                    insert_text(text);
                }
            } catch (Error e) {
                warning("Error pasting text: %s", e.message);
            }
        });
    }
    
    public void acme_snarf() {
        if (cursor.has_selection) {
            copy_selection();
        }
    }
    
    public void copy_selection() {
        string selected_text = cursor.get_selected_text(buffer);
        clipboard.set_text(selected_text);
    }
    
    // Color setters
    public void set_text_color(Gdk.RGBA color) {
        text_color = color;
        queue_draw();
    }
    
    public void set_background_color(Gdk.RGBA color) {
        bg_color = color;
        queue_draw();
    }
    
    public void set_selection_color(Gdk.RGBA color) {
        selection_color = color;
        queue_draw();
    }
    
    public void set_middle_button_dragging(bool dragging) {
        middle_button_dragging = dragging;
        queue_draw();
    }

    public void set_right_button_dragging(bool dragging) {
        right_button_dragging = dragging;
        queue_draw();
    }
    
    // Public properties for compatibility
    public int cursor_line { get { return cursor.line; } set { cursor.line = value; } }
    public int cursor_col { get { return cursor.col; } set { cursor.col = value; } }
    public bool has_selection { get { return cursor.has_selection; } set { cursor.has_selection = value; } }
    public int selection_start_line { get { return cursor.selection_start_line; } set { cursor.selection_start_line = value; } }
    public int selection_start_col { get { return cursor.selection_start_col; } set { cursor.selection_start_col = value; }  }
    public int selection_end_line { get { return cursor.selection_end_line; } set { cursor.selection_end_line = value; }  }
    public int selection_end_col { get { return cursor.selection_end_col; } set { cursor.selection_end_col = value; } }
    public string[] lines { get { return buffer.lines; } set { buffer.lines = value; } }
    public int line_count { get { return buffer.line_count; } set { buffer.line_count = value; } }
}