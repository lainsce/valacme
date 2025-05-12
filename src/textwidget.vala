/* acme_drawing_textview.vala
 * Custom text view implementation
 */

public class AcmeDrawingTextView : Gtk.DrawingArea {
    // Text content
    public string[] lines;
    public int line_count;
    
    // Cursor state
    public int cursor_line;
    public int cursor_col; 
    
    // Selection state
    public bool has_selection;
    public int selection_start_line;
    public int selection_start_col;
    public int selection_end_line;
    public int selection_end_col;
    
    // Font and layout
    public Pango.FontDescription font_desc;
    public int font_height;
    public int char_width;
    private Gee.HashMap<unichar, int>? char_width_cache;
    
    // Styling
    public Gdk.RGBA text_color;
    public Gdk.RGBA bg_color;
    public Gdk.RGBA selection_color;
    public Gdk.RGBA cursor_color;
    
    // Scroll state
    public int scroll_offset_y;
    public int visible_lines;
    
    // Margins
    public bool has_margins = false;

    public bool middle_button_dragging = false;
    public bool right_button_dragging = false;
    
    // Undo/redo support
    public signal void undo_stack_changed();
    public signal void redo_stack_changed();
    private class TextOperation {
        public enum OpType {
            INSERT,
            DELETE
        }
        
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
    
    private Gee.ArrayList<TextOperation> undo_stack;
    private Gee.ArrayList<TextOperation> redo_stack;
    private bool in_undo_operation = false;
    
    // Signals
    public signal void text_changed();
    public signal void cursor_moved();
    public signal void selection_changed();
    
    // Clipboard
    public Gdk.Clipboard clipboard;
    
    // Modify the constructor in AcmeDrawingTextView to set a yellow selection color
    public AcmeDrawingTextView(bool margins) {
        // Set up initial state
        lines = new string[1];
        lines[0] = "";
        line_count = 1;
        
        cursor_line = 0;
        cursor_col = 0;
        
        has_selection = false;
        selection_start_line = 0;
        selection_start_col = 0;
        selection_end_line = 0;
        selection_end_col = 0;
        
        scroll_offset_y = 0;
        visible_lines = 0;
        
        has_margins = margins;
        
        // Initialize undo/redo stacks
        undo_stack = new Gee.ArrayList<TextOperation>();
        redo_stack = new Gee.ArrayList<TextOperation>();
        
        // Set up DrawingArea
        this.set_size_request(400, 300);
        this.set_draw_func(draw_func);
        
        // Setup colors
        text_color = Gdk.RGBA();
        text_color.parse("#000000");
        
        bg_color = Gdk.RGBA();
        bg_color.parse("#FFFFEA");  // ACME yellow background
        
        // Use a yellow-tinted selection color to match Acme's style
        selection_color = Gdk.RGBA();
        selection_color.parse("#EEEE9E");  // Light yellow for selection
        
        cursor_color = Gdk.RGBA();
        cursor_color.parse("#000000");
        
        // Setup font
        font_desc = new Pango.FontDescription ();
        font_desc.set_family("Go");
        font_desc.set_size((int)(11 * Pango.SCALE));
        calculate_font_metrics();
        
        // Get clipboard reference
        clipboard = Gdk.Display.get_default().get_clipboard();
        
        // Set up input handling
        setup_input_handling();
    }
    
    public void set_font(string font_name) {
        // Parse the font description
        font_desc = Pango.FontDescription.from_string(font_name);
        
        // Recalculate metrics
        calculate_font_metrics();
        
        // Redraw
        this.queue_draw();
    }
    
    // Calculate font metrics
    public void calculate_font_metrics() {
        // Create a temporary Cairo context for measurement
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
        var cr = new Cairo.Context(surface);
        
        // Create a layout for measuring
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(font_desc);
        
        // 1. Get the font height (line spacing)
        layout.set_text("M", 1);
        int height_m;
        layout.get_pixel_size(null, out height_m);
        
        layout.set_text("Wy|", 3);  // Characters with descenders/ascenders
        int height_wy;
        layout.get_pixel_size(null, out height_wy);
        
        font_height = ((int)Math.fmax(height_m, height_wy)) - 2; // Normalize height
        
        // 2. Calculate average character width for tabs and default spacing
        // Use a representative ASCII character set
        string sample_chars = """abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+-={}[]\|;:'"<>,./?`~""";
        layout.set_text(sample_chars, -1);
        int total_width;
        layout.get_pixel_size(out total_width, null);
        
        char_width = total_width / sample_chars.length;
        
        // 3. Store some common character widths for optimization
        cache_common_char_widths(layout);
        
        // Clean up
        surface.finish();
    }
    private void cache_common_char_widths(Pango.Layout layout) {
        char_width_cache = new Gee.HashMap<unichar, int>();
        
        // Cache ASCII characters
        for (int i = 32; i <= 126; i++) {
            unichar c = (unichar)i;
            string str = c.to_string();
            layout.set_text(str, -1);
            int width;
            layout.get_pixel_size(out width, null);
            char_width_cache[c] = width;
        }
    }
    
    // Get the width of a specific character
    public int get_char_width(unichar c) {
        if (char_width_cache != null && char_width_cache.has_key(c)) {
            return char_width_cache[c];
        }
        
        // For characters not in cache, measure them
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
        var cr = new Cairo.Context(surface);
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(font_desc);
        
        string str = c.to_string();
        layout.set_text(str, -1);
        int width;
        layout.get_pixel_size(out width, null);
        
        surface.finish();
        return width;
    }

    // Get the width of a text string
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

    // Get the width of text up to a specific column in a line
    private int get_text_width_to_column(string line, int col) {
        if (col <= 0) return 0;
        if (col >= line.length) return get_text_width(line);
        
        string substring = line.substring(0, col);
        return get_text_width(substring);
    }

    // Convert screen x position to column position in a line
    private int x_to_column(string line, double x) {
        if (x <= 0) return 0;
        
        // Binary search to find the column
        int left = 0;
        int right = line.length;
        
        while (left < right) {
            int mid = (left + right) / 2;
            int width = get_text_width_to_column(line, mid);
            
            if (width < x) {
                left = mid + 1;
            } else {
                right = mid;
            }
        }
        
        return left;
    }
    
    // Main drawing function
    public void draw_func(Gtk.DrawingArea drawing_area, Cairo.Context cr, int width, int height) {
        // Fill background
        cr.set_source_rgba(bg_color.red, bg_color.green, bg_color.blue, bg_color.alpha);
        cr.rectangle(0, 0, width, height);
        cr.fill();
        
        Cairo.FontOptions options = new Cairo.FontOptions();
        options.set_antialias(Cairo.Antialias.GRAY);
        cr.set_font_options(options);
        
        // Calculate visible area
        visible_lines = height / font_height;
        
        // Create Pango layout for text rendering
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(font_desc);
        
        // Calculate left margin based on has_margins flag
        int left_margin = has_margins ? 16 : 0;
        
        // Draw text lines
        for (int i = scroll_offset_y; i < line_count && i < scroll_offset_y + visible_lines; i++) {
            int y = (i - scroll_offset_y) * font_height;
            
            // Draw selection if this line has any
            if (has_selection && i >= Math.fmin(selection_start_line, selection_end_line) && 
                i <= Math.fmax(selection_start_line, selection_end_line)) {
                draw_selection_for_line(cr, i, y, width, left_margin);
            }
            
            // Check if this line has selection with special coloring
            bool line_has_colored_selection = false;
            int line_sel_start = 0, line_sel_end = 0;
            
            if (has_selection && (middle_button_dragging || right_button_dragging)) {
                if (i >= Math.fmin(selection_start_line, selection_end_line) && 
                    i <= Math.fmax(selection_start_line, selection_end_line)) {
                    line_has_colored_selection = true;
                    
                    // Calculate selection bounds for this line
                    if (selection_start_line < selection_end_line || 
                        (selection_start_line == selection_end_line && selection_start_col <= selection_end_col)) {
                        // Normal selection (top to bottom)
                        line_sel_start = (i == selection_start_line) ? selection_start_col : 0;
                        line_sel_end = (i == selection_end_line) ? selection_end_col : lines[i].length;
                    } else {
                        // Reverse selection (bottom to top)
                        line_sel_start = (i == selection_end_line) ? selection_end_col : 0;
                        line_sel_end = (i == selection_start_line) ? selection_start_col : lines[i].length;
                    }
                }
            }
            
            // Draw text with appropriate coloring
            layout.set_width((int)(width * Pango.SCALE));
            layout.set_text(lines[i], -1);
            
            if (line_has_colored_selection && line_sel_start < line_sel_end) {
                // Draw text in parts: before selection, selection, after selection
                string line_text = lines[i];
                
                // Before selection
                if (line_sel_start > 0) {
                    cr.set_source_rgba(text_color.red, text_color.green, text_color.blue, text_color.alpha);
                    string before_text = line_text.substring(0, line_sel_start);
                    layout.set_text(before_text, -1);
                    cr.move_to(left_margin, y);
                    Pango.cairo_show_layout(cr, layout);
                }
                
                // Selected text (white)
                if (line_sel_end > line_sel_start) {
                    cr.set_source_rgb(1.0, 1.0, 1.0); // White text
                    string selected_text = line_text.substring(line_sel_start, line_sel_end - line_sel_start);
                    layout.set_text(selected_text, -1);
                    
                    // Calculate x position for selected text
                    int sel_x = left_margin;
                    if (line_sel_start > 0) {
                        string before_text = line_text.substring(0, line_sel_start);
                        sel_x += get_text_width(before_text);
                    }
                    
                    cr.move_to(sel_x, y);
                    Pango.cairo_show_layout(cr, layout);
                }
                
                // After selection
                if (line_sel_end < line_text.length) {
                    cr.set_source_rgba(text_color.red, text_color.green, text_color.blue, text_color.alpha);
                    string after_text = line_text.substring(line_sel_end);
                    layout.set_text(after_text, -1);
                    
                    // Calculate x position for text after selection
                    int after_x = left_margin;
                    if (line_sel_end > 0) {
                        string before_selected = line_text.substring(0, line_sel_end);
                        after_x += get_text_width(before_selected);
                    }
                    
                    cr.move_to(after_x, y);
                    Pango.cairo_show_layout(cr, layout);
                }
            } else {
                // No special coloring needed, draw normally
                cr.set_source_rgba(text_color.red, text_color.green, text_color.blue, text_color.alpha);
                cr.move_to(left_margin, y);
                Pango.cairo_show_layout(cr, layout);
            }
        }
        
        // Draw cursor regardless of selection state
        draw_cursor(cr, left_margin);
    }

    // Draw the selection highlight for a line
    public void draw_selection_for_line(Cairo.Context cr, int line, int y, int width, int left_margin = 0) {
        // Calculate selection bounds for this line
        int start_col, end_col;
        
        if (selection_start_line < selection_end_line || 
            (selection_start_line == selection_end_line && selection_start_col <= selection_end_col)) {
            // Normal selection (top to bottom)
            start_col = (line == selection_start_line) ? selection_start_col : 0;
            end_col = (line == selection_end_line) ? selection_end_col : lines[line].length;
        } else {
            // Reverse selection (bottom to top)
            start_col = (line == selection_end_line) ? selection_end_col : 0;
            end_col = (line == selection_start_line) ? selection_start_col : lines[line].length;
        }
        
        // Convert columns to x positions using actual text width
        int start_x = left_margin;
        if (start_col > 0) {
            string text_before_start = lines[line].substring(0, start_col);
            start_x += get_text_width(text_before_start);
        }
        
        int end_x = left_margin;
        if (end_col > 0) {
            string text_before_end = lines[line].substring(0, end_col);
            end_x += get_text_width(text_before_end);
        }
        
        // Choose color based on which button is dragging
        if (middle_button_dragging) {
            cr.set_source_rgb(1.0, 0.0, 0.0); // Bright red for button2
        } else if (right_button_dragging) {
            cr.set_source_rgb(0.0, 0.8, 0.0); // Green for button3
        } else {
            cr.set_source_rgba(selection_color.red, selection_color.green, selection_color.blue, selection_color.alpha);
        }
        
        // Draw selection background
        cr.rectangle(start_x, y, end_x - start_x, font_height);
        cr.fill();
    }
    
    // Draw the text cursor
    public void draw_cursor(Cairo.Context cr, int left_margin = 0) {
        // Calculate x position using actual text width
        int x = left_margin;
        if (cursor_col > 0 && cursor_line < line_count) {
            string text_before_cursor = lines[cursor_line].substring(0, cursor_col);
            x += get_text_width(text_before_cursor);
        }
        
        int y = (cursor_line - scroll_offset_y) * font_height;
        
        // Only draw if cursor is visible on screen
        if (cursor_line >= scroll_offset_y && cursor_line < scroll_offset_y + visible_lines) {
            cr.set_source_rgba(cursor_color.red, cursor_color.green, cursor_color.blue, 1.0);
            cr.set_antialias(Cairo.Antialias.NONE); // Crisp 1px line
            cr.set_line_width(1.0);
            
            // Match Plan 9's cursor style but with precise positioning
            cr.rectangle(x, y, 3, 3);
            cr.fill();
            cr.move_to(x + 2, y);
            cr.line_to(x + 2, y + font_height - 3);
            cr.stroke();
            cr.rectangle(x, y + font_height - 3, 3, 3);
            cr.fill();
        }
    }
        
    // Setup input handling (keyboard and mouse)
    public void setup_input_handling() {
        // Make widget focusable and can grab focus
        this.set_focusable(true);
        this.set_can_focus(true);
        
        // Ensure we grab focus on click
        this.set_focus_on_click(true);
        
        // Key event controller
        var key_controller = new Gtk.EventControllerKey();
        key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        this.add_controller(key_controller);
        
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            // Handle the key press
            bool handled = handle_key_press(keyval, state);
            
            // Ensure cursor visibility after any key press
            ensure_cursor_visible();
            
            // Redraw to show cursor movement
            this.queue_draw();
            
            // Return true to stop propagation if we handled it
            return handled;
        });
        
        // Focus event handler to ensure proper focus management
        var focus_controller = new Gtk.EventControllerFocus();
        this.add_controller(focus_controller);
        
        focus_controller.enter.connect(() => {
            // Ensure we have focus
            this.grab_focus();
        });
        
        // Mouse event controllers
        var click = new Gtk.GestureClick();
        click.set_button(1); // Left click for cursor positioning
        this.add_controller(click);
        
        click.pressed.connect((n_press, x, y) => {
            // Position cursor based on click position
            position_cursor_at_point((int)x, (int)y);
            
            // Clear selection
            clear_selection();
            start_selection();
            
            // Request focus
            this.grab_focus();
            
            // Ensure cursor is visible
            this.queue_draw();
        });
        
        // Drag for text selection
        var drag = new Gtk.GestureDrag();
        this.add_controller(drag);
        
        drag.drag_begin.connect((start_x, start_y) => {
            // In GTK4, we can set the drag gesture to track a specific button
            // Since we're setting up multiple gestures for different buttons, we can
            // customize the GestureDrag to be specific to a button
            
            // Check if the drag gesture was set up for a specific button
            if (drag is Gtk.GestureSingle) {
                var single_gesture = (Gtk.GestureSingle)drag;
                uint button = single_gesture.get_current_button();
                
                middle_button_dragging = (button == 2);
                right_button_dragging = (button == 3);
            }
            
            // Start selection at cursor position
            position_cursor_at_point((int)start_x, (int)start_y);
            start_selection();
        });
        
        drag.drag_update.connect((offset_x, offset_y) => {
            // Get current position
            double start_x, start_y;
            drag.get_start_point(out start_x, out start_y);
            
            // Calculate current point
            double current_x = start_x + offset_x;
            double current_y = start_y + offset_y;
            
            // Update selection to include from start point to current point
            update_selection_at_point((int)current_x, (int)current_y);
            
            // Make sure we keep getting the events
            drag.set_state(Gtk.EventSequenceState.CLAIMED);
        });
        
        drag.drag_end.connect(() => {
            middle_button_dragging = false;
            right_button_dragging = false;
            this.queue_draw();
        });
            
        // Scroll controller for scrolling
        var scroll = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.VERTICAL);
        this.add_controller(scroll);
        
        scroll.scroll.connect((dx, dy) => {
            // Scroll text by lines
            int lines_to_scroll = (int)(dy > 0 ? 3 : -3); // 3 lines per scroll event
            scroll_by_lines(lines_to_scroll);
            return true; // Handled
        });
    }
    
    public void set_middle_button_dragging(bool dragging) {
        middle_button_dragging = dragging;
        this.queue_draw();
    }

    public void set_right_button_dragging(bool dragging) {
        right_button_dragging = dragging;
        this.queue_draw();
    }
    
    // Handle key press events
    public bool handle_key_press(uint keyval, Gdk.ModifierType state) {
        switch (keyval) {
            case Gdk.Key.Up:
                move_cursor_up();
                return true; // Handled
                
            case Gdk.Key.Down:
                move_cursor_down();
                return true; // Handled
                
            case Gdk.Key.Left:
                move_cursor_left();
                return true; // Handled
                
            case Gdk.Key.Right:
                move_cursor_right();
                return true; // Handled
                
            case Gdk.Key.Home:
                move_cursor_to_line_start();
                return true; // Handled
                
            case Gdk.Key.End:
                move_cursor_to_line_end();
                return true; // Handled
                
            case Gdk.Key.Page_Up:
                page_up();
                return true; // Handled
                
            case Gdk.Key.Page_Down:
                page_down();
                return true; // Handled
                
            case Gdk.Key.BackSpace:
                delete_backward();
                return true; // Handled
                
            case Gdk.Key.Delete:
                delete_forward();
                return true; // Handled
                
            case Gdk.Key.Return:
            case Gdk.Key.KP_Enter:
                insert_newline();
                return true; // Handled
                
            case Gdk.Key.Tab:
                insert_text("    "); // 4 spaces for tab
                return true; // Handled
                
            default:
                // Handle normal text input
                if (keyval >= 32 && keyval <= 126) { // Printable ASCII
                    char c = (char)keyval;
                    string s = c.to_string();
                    insert_text(s);
                    return true;
                }
                return true; // Handled
        }
    }

    // Position cursor at point (x, y)
    public void position_cursor_at_point(int x, int y) {
        // Calculate line from y position
        int line = scroll_offset_y + (y / font_height);
        if (line >= line_count) line = line_count - 1;
        if (line < 0) line = 0;
        
        // Account for left margin when calculating column
        int adjusted_x = x;
        if (has_margins) {
            adjusted_x = (int)Math.fmax(0, x - 17);
        }
        
        // Convert x position to column using proportional width
        int col = 0;
        if (line < line_count) {
            col = x_to_column(lines[line], adjusted_x);
            if (col > lines[line].length) col = lines[line].length;
        }
        
        // Update cursor position
        cursor_line = line;
        cursor_col = col;
        cursor_moved();
        
        // Redraw
        this.queue_draw();
    }
    
    // Start a new selection at current cursor position
    public void start_selection() {
        has_selection = true;
        selection_start_line = cursor_line;
        selection_start_col = cursor_col;
        selection_end_line = cursor_line;
        selection_end_col = cursor_col;
        selection_changed();
        this.queue_draw();
    }
    
    // Update selection end point
    public void update_selection_at_point(int x, int y) {
        // Account for left margin when calculating cursor position
        int adjusted_x = x;
        if (has_margins) {
            adjusted_x = (int)Math.fmax(0, x - 17);
        }
        
        // Calculate line from y position
        int line = scroll_offset_y + (y / font_height);
        if (line >= line_count) line = line_count - 1;
        if (line < 0) line = 0;
        
        // Convert x position to column
        int col = 0;
        if (line < line_count) {
            col = x_to_column(lines[line], adjusted_x);
            if (col > lines[line].length) col = lines[line].length;
        }
        
        // Update cursor position
        cursor_line = line;
        cursor_col = col;
        
        // Update selection end
        selection_end_line = cursor_line;
        selection_end_col = cursor_col;
        
        cursor_moved();
        selection_changed();
        this.queue_draw();
    }
    
    // Clear the current selection
    public void clear_selection() {
        if (has_selection) {
            // Position cursor at the end of selection before clearing
            cursor_line = selection_end_line;
            cursor_col = selection_end_col;
            
            has_selection = false;
            selection_changed();
            this.queue_draw();
        }
    }

     // Select all text
    public void select_all() {
        has_selection = true;
        selection_start_line = 0;
        selection_start_col = 0;
        selection_end_line = line_count - 1;
        selection_end_col = lines[line_count - 1].length;
        selection_changed();
        this.queue_draw();
    }
    
    // Basic cursor movement methods
    public void move_cursor_up() {
        if (cursor_line > 0) {
            cursor_line--;
            // Adjust column if needed
            if (cursor_col > lines[cursor_line].length)
                cursor_col = lines[cursor_line].length;
            cursor_moved();
            ensure_cursor_visible();
            this.queue_draw();
        }
    }
    
    public void move_cursor_down() {
        if (cursor_line < line_count - 1) {
            cursor_line++;
            // Adjust column if needed
            if (cursor_col > lines[cursor_line].length)
                cursor_col = lines[cursor_line].length;
            cursor_moved();
            ensure_cursor_visible();
            this.queue_draw();
        }
    }
    
    public void move_cursor_left() {
        if (cursor_col > 0) {
            cursor_col--;
        } else if (cursor_line > 0) {
            cursor_line--;
            cursor_col = lines[cursor_line].length;
        }
        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    public void move_cursor_right() {
        if (cursor_col < lines[cursor_line].length) {
            cursor_col++;
        } else if (cursor_line < line_count - 1) {
            cursor_line++;
            cursor_col = 0;
        }
        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    public void move_cursor_to_line_start() {
        cursor_col = 0;
        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    public void move_cursor_to_line_end() {
        cursor_col = lines[cursor_line].length;
        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    public void page_up() {
        // Move cursor up by visible_lines - 1
        int move_lines = visible_lines - 1;
        if (move_lines < 1) move_lines = 1;
        
        if (cursor_line >= move_lines) {
            cursor_line -= move_lines;
        } else {
            cursor_line = 0;
        }
        
        // Adjust column if needed
        if (cursor_col > lines[cursor_line].length)
            cursor_col = lines[cursor_line].length;
        
        // Also scroll
        scroll_offset_y -= move_lines;
        if (scroll_offset_y < 0) scroll_offset_y = 0;
        
        cursor_moved();
        this.queue_draw();
    }
    
    public void page_down() {
        // Move cursor down by visible_lines - 1
        int move_lines = visible_lines - 1;
        if (move_lines < 1) move_lines = 1;
        
        if (cursor_line + move_lines < line_count) {
            cursor_line += move_lines;
        } else {
            cursor_line = line_count - 1;
        }
        
        // Adjust column if needed
        if (cursor_col > lines[cursor_line].length)
            cursor_col = lines[cursor_line].length;
        
        // Also scroll
        scroll_offset_y += move_lines;
        if (scroll_offset_y > line_count - visible_lines)
            scroll_offset_y = (int)Math.fmax(0, line_count - visible_lines);
        
        cursor_moved();
        this.queue_draw();
    }
    
    public void scroll_by_lines(int num_lines) {
        scroll_offset_y += num_lines;
        
        // Enforce bounds
        if (scroll_offset_y < 0) scroll_offset_y = 0;
        if (scroll_offset_y > line_count - visible_lines)
            scroll_offset_y = (int)Math.fmax(0, line_count - visible_lines);
        
        this.queue_draw();
    }
    
    // Scroll to end of text
    public void scroll_to_end() {
        if (line_count > visible_lines) {
            scroll_offset_y = line_count - visible_lines;
        } else {
            scroll_offset_y = 0;
        }
        this.queue_draw();
    }
    
    // Scroll to a specific line and column
    public void scroll_to_line_column(int line, int column) {
        // Ensure line is within bounds
        if (line < 0) line = 0;
        if (line >= line_count) line = line_count - 1;
        
        // Ensure column is within bounds
        if (column < 0) column = 0;
        if (column > lines[line].length) column = lines[line].length;
        
        // Position cursor
        cursor_line = line;
        cursor_col = column;
        
        // Scroll to make the cursor visible
        if (cursor_line < scroll_offset_y) {
            scroll_offset_y = cursor_line;
        } else if (cursor_line >= scroll_offset_y + visible_lines) {
            scroll_offset_y = cursor_line - visible_lines + 1;
        }
        
        cursor_moved();
        this.queue_draw();
    }
    
    // Make sure cursor is visible by scrolling if needed
    public void ensure_cursor_visible() {
        // If cursor is above visible area, scroll up
        if (cursor_line < scroll_offset_y) {
            scroll_offset_y = cursor_line;
        }
        // If cursor is below visible area, scroll down
        else if (cursor_line >= scroll_offset_y + visible_lines) {
            scroll_offset_y = cursor_line - visible_lines + 1;
        }
    }
    
    // Get the word at the current cursor position
    public string get_word_at_cursor() {
        if (cursor_line >= line_count) return "";
        
        string line = lines[cursor_line];
        if (cursor_col >= line.length) return "";
        
        // Find start of word
        int start = cursor_col;
        while (start > 0 && is_word_char(line[start - 1])) {
            start--;
        }
        
        // Find end of word
        int end = cursor_col;
        while (end < line.length && is_word_char(line[end])) {
            end++;
        }
        
        if (start == end) return "";
        
        return line.substring(start, end - start);
    }
    
    // Get the line at the current cursor position
    public string get_line_at_cursor() {
        if (cursor_line >= line_count) return "";
        return lines[cursor_line];
    }
    
    // Check if character is a word character (alphanumeric or underscore)
    private bool is_word_char(char c) {
        return c.isalnum() || c == '_';
    }
    
    // Record an operation for undo/redo
    private void record_operation(TextOperation op) {
        if (in_undo_operation) return;
        
        undo_stack.add(op);
        redo_stack.clear();
        
        // Emit signal that undo stack changed
        undo_stack_changed();
        redo_stack_changed(); // Since redo stack was cleared
    }
    // Add a new undo point for insert operation
    private void add_insert_undo(string text, int start_line, int start_col) {
        record_operation(new TextOperation(TextOperation.OpType.INSERT, text, start_line, start_col));
    }
    
    // Add a new undo point for delete operation
    private void add_delete_undo(string text, int start_line, int start_col, int end_line, int end_col) {
        record_operation(new TextOperation(TextOperation.OpType.DELETE, text, start_line, start_col, end_line, end_col));
    }
    
    // Undo the last operation
    public void undo() {
        if (undo_stack.size == 0) return;
        
        in_undo_operation = true;
        
        // Get the last operation
        var op = undo_stack.remove_at(undo_stack.size - 1);
        redo_stack.add(op);
        
        if (op.op_type == TextOperation.OpType.INSERT) {
            // To undo an insert, delete the inserted text
            cursor_line = op.start_line;
            cursor_col = op.start_col;
            
            // Delete the inserted text
            if (op.text.contains("\n")) {
                // Multi-line text requires special handling
                string[] lines = op.text.split("\n");
                int last_line = op.start_line + lines.length - 1;
                int last_col = lines[lines.length - 1].length;
                
                // Position selection to cover the inserted text
                has_selection = true;
                selection_start_line = op.start_line;
                selection_start_col = op.start_col;
                selection_end_line = last_line;
                selection_end_col = op.start_col + last_col;
                
                // Delete the selection
                delete_selection();
            } else {
                // Single line text is simpler
                for (int i = 0; i < op.text.length; i++) {
                    delete_forward();
                }
            }
        } else if (op.op_type == TextOperation.OpType.DELETE) {
            // To undo a delete, insert the deleted text
            cursor_line = op.start_line;
            cursor_col = op.start_col;
            
            // Insert the deleted text
            insert_text(op.text);
            
            // Position cursor at the original position after the insert
            cursor_line = op.start_line;
            cursor_col = op.start_col;
        }
        
        in_undo_operation = false;
        ensure_cursor_visible();
        this.queue_draw();
        
        // Emit signals that stacks have changed
        undo_stack_changed();
        redo_stack_changed();
    }
    
    // Redo the last undone operation
    public void redo() {
        if (redo_stack.size == 0) return;
        
        in_undo_operation = true;
        
        // Get the last undone operation
        var op = redo_stack.remove_at(redo_stack.size - 1);
        undo_stack.add(op);
        
        if (op.op_type == TextOperation.OpType.INSERT) {
            // To redo an insert, insert the text again
            cursor_line = op.start_line;
            cursor_col = op.start_col;
            
            // Insert the text
            insert_text(op.text);
        } else if (op.op_type == TextOperation.OpType.DELETE) {
            // To redo a delete, delete the text again
            cursor_line = op.start_line;
            cursor_col = op.start_col;
            
            // Position selection to cover the text to delete
            has_selection = true;
            selection_start_line = op.start_line;
            selection_start_col = op.start_col;
            selection_end_line = op.end_line;
            selection_end_col = op.end_col;
            
            // Delete the selection
            delete_selection();
        }
        
        in_undo_operation = false;
        ensure_cursor_visible();
        this.queue_draw();
        
        // Emit signals that stacks have changed
        undo_stack_changed();
        redo_stack_changed();
    }
    
    // Text editing methods
    public void insert_text(string text) {
        // First delete any selected text
        if (has_selection) {
            delete_selection();
        }
        
        // Record the insert operation for undo
        add_insert_undo(text, cursor_line, cursor_col);
        
        // Handle newlines in the text
        if (text.contains("\n")) {
            string[] new_lines = text.split("\n");
            
            // First line: insert at cursor position
            string first_line = lines[cursor_line];
            string first_part = first_line.substring(0, cursor_col);
            string last_part = first_line.substring(cursor_col);
            
            // Update the first line
            lines[cursor_line] = first_part + new_lines[0];
            
            // Calculate how many new lines we need to add
            int new_line_count = new_lines.length - 1;
            
            // Ensure enough space for new lines by expanding the array if needed
            if (line_count + new_line_count >= lines.length) {
                // Create a larger array with enough space for all our lines and then some
                int new_capacity = (int)Math.fmax(lines.length * 2, line_count + new_line_count + 10);
                string[] expanded_lines = new string[new_capacity];
                
                // Copy existing lines to the new array
                for (int i = 0; i < line_count; i++) {
                    expanded_lines[i] = lines[i];
                }
                
                // Update our lines reference to the new array
                lines = expanded_lines;
            }
            
            // If we're inserting multiple lines, make space for them
            if (new_line_count > 0) {
                // Shift existing lines down to make room
                for (int i = line_count + new_line_count - 1; i > cursor_line + new_line_count; i--) {
                    lines[i] = lines[i - new_line_count];
                }
                
                // Insert the middle lines (if any)
                for (int i = 1; i < new_lines.length; i++) {
                    lines[cursor_line + i] = (i == new_lines.length - 1) ? 
                        new_lines[i] + last_part : // Last line gets the remainder of original line
                        new_lines[i];              // Middle lines are inserted as-is
                }
                
                // Update line count
                line_count += new_line_count;
                
                // Position cursor at end of inserted text
                cursor_line = cursor_line + new_line_count;
                cursor_col = new_lines[new_line_count].length;
            }
        } else {
            // Simple case: insert text at cursor position
            string line = lines[cursor_line];
            string new_line = line.substring(0, cursor_col) + text + line.substring(cursor_col);
            lines[cursor_line] = new_line;
            
            // Move cursor forward
            cursor_col += text.length;
        }

        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    public void insert_newline() {
        // First delete any selected text
        if (has_selection) {
            delete_selection();
        }
        
        // Record the insert operation for undo
        add_insert_undo("\n", cursor_line, cursor_col);
        
        // Split current line at cursor
        string line = lines[cursor_line];
        string line1 = line.substring(0, cursor_col);
        string line2 = line.substring(cursor_col);
        
        // Update current line
        lines[cursor_line] = line1;
        
        // Insert new line
        if (cursor_line + 1 < line_count) {
            // Make room for new line
            for (int i = line_count; i > cursor_line + 1; i--) {
                lines[i] = lines[i - 1];
            }
            lines[cursor_line + 1] = line2;
        } else {
            // Append new line
            if (line_count >= lines.length) {
                // Resize array if needed
                string[] new_lines = new string[lines.length * 2];
                for (int i = 0; i < line_count; i++) {
                    new_lines[i] = lines[i];
                }
                lines = new_lines;
            }
            
            lines[line_count] = line2;
        }
        
        line_count++;
        
        // Move cursor to beginning of new line
        cursor_line++;
        cursor_col = 0;
        
        text_changed();
        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    public void delete_backward() {
        // If we have a selection, delete it
        if (has_selection) {
            delete_selection();
            return;
        }
        
        // Delete character before cursor
        if (cursor_col > 0) {
            // Record the delete operation for undo
            string deleted_text = lines[cursor_line].substring(cursor_col - 1, 1);
            add_delete_undo(deleted_text, cursor_line, cursor_col - 1, cursor_line, cursor_col);
            
            // Delete within current line
            string line = lines[cursor_line];
            string new_line = line.substring(0, cursor_col - 1) + line.substring(cursor_col);
            lines[cursor_line] = new_line;
            cursor_col--;
        } else if (cursor_line > 0) {
            // Record the delete operation for undo
            string deleted_text = "\n";
            add_delete_undo(deleted_text, cursor_line - 1, lines[cursor_line - 1].length, cursor_line, 0);
            
            // Merge with previous line
            string prev_line = lines[cursor_line - 1];
            string curr_line = lines[cursor_line];
            
            // Move cursor to end of previous line
            cursor_line--;
            cursor_col = prev_line.length;
            
            // Merge lines
            lines[cursor_line] = prev_line + curr_line;
            
            // Shift remaining lines up
            for (int i = cursor_line + 1; i < line_count - 1; i++) {
                lines[i] = lines[i + 1];
            }
            line_count--;
        }
        
        text_changed();
        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    public void delete_forward() {
        // If we have a selection, delete it
        if (has_selection) {
            delete_selection();
            return;
        }
        
        // Delete character after cursor
        if (cursor_col < lines[cursor_line].length) {
            // Record the delete operation for undo
            string deleted_text = lines[cursor_line].substring(cursor_col, 1);
            add_delete_undo(deleted_text, cursor_line, cursor_col, cursor_line, cursor_col + 1);
            
            // Delete within current line
            string line = lines[cursor_line];
            string new_line = line.substring(0, cursor_col) + line.substring(cursor_col + 1);
            lines[cursor_line] = new_line;
        } else if (cursor_line < line_count - 1) {
            // Record the delete operation for undo
            string deleted_text = "\n";
            add_delete_undo(deleted_text, cursor_line, cursor_col, cursor_line + 1, 0);
            
            // Merge with next line
            string curr_line = lines[cursor_line];
            string next_line = lines[cursor_line + 1];
            
            // Merge lines
            lines[cursor_line] = curr_line + next_line;
            
            // Shift remaining lines up
            for (int i = cursor_line + 1; i < line_count - 1; i++) {
                lines[i] = lines[i + 1];
            }
            line_count--;
        }
        
        text_changed();
        this.queue_draw();
    }
    
    public void delete_selection() {
        if (!has_selection) return;
        
        // Record the delete operation for undo
        string deleted_text = get_selected_text();
        add_delete_undo(deleted_text, selection_start_line, selection_start_col, selection_end_line, selection_end_col);
        
        // Handle single line selection
        if (selection_start_line == selection_end_line) {
            string line = lines[selection_start_line];
            string new_line = line.substring(0, selection_start_col) + 
                             line.substring(selection_end_col);
            lines[selection_start_line] = new_line;
            
            // Move cursor to start of selection
            cursor_line = selection_start_line;
            cursor_col = selection_start_col;
        } else {
            // Handle multi-line selection
            // Modify first line
            string first_line = lines[selection_start_line];
            string last_line = lines[selection_end_line];
            
            // Create merged line from parts outside selection
            string merged_line = first_line.substring(0, selection_start_col) + 
                                last_line.substring(selection_end_col);
            
            // Set first line to merged content
            lines[selection_start_line] = merged_line;
            
            // Remove lines in between
            int lines_to_remove = selection_end_line - selection_start_line;
            for (int i = selection_start_line + 1; i < line_count - lines_to_remove; i++) {
                lines[i] = lines[i + lines_to_remove];
            }
            
            line_count -= lines_to_remove;
            
            // Move cursor to start of selection
            cursor_line = selection_start_line;
            cursor_col = selection_start_col;
        }
        
        // Clear selection
        has_selection = false;
        
        text_changed();
        cursor_moved();
        ensure_cursor_visible();
        this.queue_draw();
    }
    
    // Cut, copy, paste operations
    public void cut_selection() {
        if (!has_selection) return;
        
        // First copy
        copy_selection();
        
        // Then delete
        delete_selection();
    }
    
    public void copy_selection() {
        if (!has_selection) return;
        
        // Extract selected text
        string selected_text = get_selected_text();
        
        // Copy to clipboard
        clipboard.set_text(selected_text);
    }
    
    public void paste_text() {
        // Request text from clipboard
        clipboard.read_text_async.begin(null, (obj, res) => {
            try {
                string? text = clipboard.read_text_async.end(res);
                if (text != null && text != "") {
                    // Delete any selected text first
                    if (has_selection) {
                        delete_selection();
                    }
                    
                    // Insert the pasted text
                    insert_text(text);
                }
            } catch (Error e) {
                warning("Error pasting text: %s", e.message);
            }
        });
    }
    
    // Get the selected text as a string
    public string get_selected_text() {
        if (!has_selection) return "";
        
        // Handle single line selection
        if (selection_start_line == selection_end_line) {
            string line = lines[selection_start_line];
            return line.substring(selection_start_col, selection_end_col - selection_start_col);
        }
        
        // Handle multi-line selection
        StringBuilder sb = new StringBuilder();
        
        // First line
        string first_line = lines[selection_start_line];
        sb.append(first_line.substring(selection_start_col));
        sb.append("\n");
        
        // Middle lines
        for (int i = selection_start_line + 1; i < selection_end_line; i++) {
            sb.append(lines[i]);
            sb.append("\n");
        }
        
        // Last line
        string last_line = lines[selection_end_line];
        sb.append(last_line.substring(0, selection_end_col));
        
        return sb.str;
    }
    
    // Methods to access text content
    public string get_text() {
        StringBuilder sb = new StringBuilder();
        
        for (int i = 0; i < line_count; i++) {
            sb.append(lines[i]);
            if (i < line_count - 1) {
                sb.append("\n");
            }
        }
        
        return sb.str;
    }
    
    public void set_text(string text, bool cursor_at_end = false) {
        // Split into lines
        string[] new_lines = text.split("\n");
        int new_line_count = new_lines.length;
        
        // Ensure our array is large enough
        if (new_line_count > lines.length) {
            lines = new string[new_line_count * 2];
        }
        
        // Copy lines
        for (int i = 0; i < new_line_count; i++) {
            lines[i] = new_lines[i];
        }
        
        line_count = new_line_count;
        
        if (cursor_at_end) {
            // Position cursor at the end of the last line
            cursor_line = line_count - 1;
            cursor_col = lines[cursor_line].length;
        } else {
            // Reset cursor position to beginning
            cursor_line = 0;
            cursor_col = 0;
        }
        
        // Reset scroll position to top
        scroll_offset_y = 0;
        
        // Clear selection
        has_selection = false;
        
        // Clear undo/redo stacks
        undo_stack.clear();
        redo_stack.clear();
        
        text_changed();
        cursor_moved();
        this.queue_draw();
    }
    
    public void scroll_to_top() {
        scroll_offset_y = 0;
        this.queue_draw();
    }
    
    // Set the text color
    public void set_text_color(Gdk.RGBA color) {
        text_color = color;
        this.queue_draw();
    }
    
    // Set the background color
    public void set_background_color(Gdk.RGBA color) {
        bg_color = color;
        this.queue_draw();
    }
    
    // Set the background color
    public void set_selection_color(Gdk.RGBA color) {
        selection_color = color;
        this.queue_draw();
    }
    
    public bool can_undo() {
        return undo_stack.size > 0;
    }

    public bool can_redo() {
        return redo_stack.size > 0;
    }
    
    public bool is_modified() {
        // Return true if there are any changes since the last save point
        // This could be more sophisticated with a "save point" in the undo stack
        return undo_stack.size > 0;
    }
    
    // Public interface methods for ACME
    
    // ACME-specific cut operation (like button1+button2)
    public void acme_cut() {
        if (has_selection) {
            cut_selection();
        }
    }
    
    // ACME-specific paste operation (like button1+button3)
    public void acme_paste() {
        paste_text();
    }
    
    // ACME-specific snarf (copy)
    public void acme_snarf() {
        if (has_selection) {
            copy_selection();
        }
    }
}