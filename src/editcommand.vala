/* editcommand.vala
 * Edit command implementation for ACME Vala with enhanced address syntax
 * Adapted for AcmeDrawingTextView (not Gtk.TextBuffer)
 */

public class AcmeEditCommand : Object {
    // Enhanced AddressType enum
    public enum AddressType {
        LINE_NUMBER,
        DOT,          // Current position
        DOLLAR,       // End of file
        REGEX,        // /pattern/ or ?pattern?
        PLUS,         // +n
        MINUS,        // -n
        CHAR_OFFSET,  // #n
        NONE
    }
    
    // Enhanced Address class
    public class Address {
        public AddressType type;
        public string value;
        public bool reverse;  // For ?pattern? (reverse search)
        
        public Address(AddressType type, string value = "", bool reverse = false) {
            this.type = type;
            this.value = value;
            this.reverse = reverse;
        }
    }
    
    // Enhanced AddressRange class
    public class AddressRange {
        public Address? start;
        public Address? end;
        public string operator;  // "," or ";"
        
        public AddressRange() {
            start = null;
            end = null;
            operator = ",";
        }
    }
    
    // Text position class
    public class TextPosition {
        public int line;
        public int col;
        
        public TextPosition(int line, int col) {
            this.line = line;
            this.col = col;
        }
    }
    
    // Enhanced address parser
    private class AddressParser {
        private string text;
        private int pos;
        
        public AddressParser(string address_text) {
            this.text = address_text;
            this.pos = 0;
        }
        
        public AddressRange? parse() {
            var range = new AddressRange();
            
            // Parse first address
            range.start = parse_single_address();
            
            // Check for range operator
            if (pos < text.length) {
                char op = text[pos];
                if (op == ',' || op == ';') {
                    range.operator = op.to_string();
                    pos++;
                    
                    // Parse second address
                    range.end = parse_single_address();
                }
            }
            
            return range;
        }
        
        private Address? parse_single_address() {
            if (pos >= text.length) return null;
            
            char c = text[pos];
            
            switch (c) {
                case '.':
                    pos++;
                    return new Address(AddressType.DOT);
                    
                case '$':
                    pos++;
                    return new Address(AddressType.DOLLAR);
                    
                case '#':
                    pos++;
                    return parse_char_offset();
                    
                case '/':
                    return parse_regex(false);
                    
                case '?':
                    return parse_regex(true);
                    
                case '+':
                    pos++;
                    return parse_relative(AddressType.PLUS);
                    
                case '-':
                    pos++;
                    return parse_relative(AddressType.MINUS);
                    
                default:
                    if (c.isdigit()) {
                        return parse_line_number();
                    }
                    break;
            }
            
            return null;
        }
        
        private Address parse_char_offset() {
            string num = "";
            while (pos < text.length && text[pos].isdigit()) {
                num += text[pos].to_string();
                pos++;
            }
            return new Address(AddressType.CHAR_OFFSET, num);
        }
        
        private Address parse_regex(bool reverse) {
            char delimiter = reverse ? '?' : '/';
            pos++; // Skip opening delimiter
            
            StringBuilder pattern = new StringBuilder();
            while (pos < text.length && text[pos] != delimiter) {
                if (text[pos] == '\\' && pos + 1 < text.length) {
                    // Handle escaped characters
                    pos++;
                    pattern.append_c(text[pos]);
                } else {
                    pattern.append_c(text[pos]);
                }
                pos++;
            }
            
            if (pos < text.length) pos++; // Skip closing delimiter
            
            return new Address(AddressType.REGEX, pattern.str, reverse);
        }
        
        private Address parse_line_number() {
            StringBuilder num = new StringBuilder();
            while (pos < text.length && text[pos].isdigit()) {
                num.append_c(text[pos]);
                pos++;
            }
            return new Address(AddressType.LINE_NUMBER, num.str);
        }
        
        private Address parse_relative(AddressType type) {
            StringBuilder num = new StringBuilder();
            while (pos < text.length && text[pos].isdigit()) {
                num.append_c(text[pos]);
                pos++;
            }
            
            // If no number, default to 1
            if (num.len == 0) {
                num.append("1");
            }
            
            return new Address(type, num.str);
        }
    }
    
    private static AcmeEditCommand? instance;
    
    private AcmeEditCommand() {
    }
    
    public static AcmeEditCommand get_instance() {
        if (instance == null) {
            instance = new AcmeEditCommand();
        }
        return instance;
    }
    
    // Main execute method
    public bool execute(string command, AcmeTextView view) {
        // Parse command into address and operation parts
        var parts = split_address_command(command);
        if (parts.length < 1) return false;
        
        if (parts.length == 1) {
            // No explicit address, check for commands with implicit addresses
            if (command.has_prefix("s/")) {
                // Substitute without explicit address - use current selection or line
                return execute_substitute(command.substring(1), view);
            }
            return false;
        }
        
        string address_str = parts[0];
        string operation = parts[1];
        
        // Parse and evaluate the address
        var parser = new AddressParser(address_str);
        var range = parser.parse();
        
        if (range == null) return false;
        
        TextPosition start, end;
        if (!evaluate_range(range, view, out start, out end)) return false;
        
        // Select the addressed range
        var text_view = view.text_view;
        text_view.has_selection = true;
        text_view.selection_start_line = start.line;
        text_view.selection_start_col = start.col;
        text_view.selection_end_line = end.line;
        text_view.selection_end_col = end.col;
        
        // Position cursor at end of selection
        text_view.cursor_line = end.line;
        text_view.cursor_col = end.col;
        
        // Execute the operation
        return execute_operation_at_range(operation, start, end, view);
    }
    
    // Helper to split address from command
    private string[] split_address_command(string command) {
        int cmd_start = -1;
        
        // Look for space after address pattern
        bool in_regex = false;
        char regex_char = '\0';
        
        for (int i = 0; i < command.length; i++) {
            char c = command[i];
            
            if (c == '/' || c == '?') {
                if (!in_regex) {
                    in_regex = true;
                    regex_char = c;
                } else if (c == regex_char) {
                    in_regex = false;
                }
            } else if (!in_regex && c.isspace()) {
                cmd_start = i;
                break;
            }
        }
        
        if (cmd_start > 0) {
            return {
                command.substring(0, cmd_start).strip(),
                command.substring(cmd_start).strip()
            };
        }
        
        return { command };
    }
    
    // Enhanced range evaluation
    private bool evaluate_range(AddressRange range, AcmeTextView view, 
                               out TextPosition start, out TextPosition end) {
        var text_view = view.text_view;
        end = new TextPosition(0, 0);
        
        if (range.start == null) {
            // Default to current position/selection
            if (text_view.has_selection) {
                start = new TextPosition(text_view.selection_start_line, text_view.selection_start_col);
                end = new TextPosition(text_view.selection_end_line, text_view.selection_end_col);
            } else {
                start = new TextPosition(text_view.cursor_line, text_view.cursor_col);
                end = new TextPosition(text_view.cursor_line, text_view.cursor_col);
            }
        } else {
            if (!evaluate_address(range.start, view, out start)) {
                return false;
            }
        }
        
        if (range.end == null) {
            // Single address - set end to start
            end = new TextPosition(start.line, start.col);
        } else {
            // Handle semicolon operator (change context)
            if (range.operator == ";") {
                // For semicolon, move cursor to first address position
                text_view.cursor_line = start.line;
                text_view.cursor_col = start.col;
            }
            
            if (!evaluate_address(range.end, view, out end)) {
                return false;
            }
        }
        
        // Ensure start comes before end
        if (start.line > end.line || (start.line == end.line && start.col > end.col)) {
            var temp = new TextPosition(start.line, start.col);
            start = new TextPosition(end.line, end.col);
            end = temp;
        }
        
        return true;
    }
    
    // Enhanced address evaluation
    private bool evaluate_address(Address addr, AcmeTextView view, out TextPosition pos) {
        var text_view = view.text_view;
        
        switch (addr.type) {
            case AddressType.DOT:
                pos = new TextPosition(text_view.cursor_line, text_view.cursor_col);
                return true;
                
            case AddressType.DOLLAR:
                pos = new TextPosition(text_view.line_count - 1, text_view.lines[text_view.line_count - 1].length);
                return true;
                
            case AddressType.LINE_NUMBER:
                int line = int.parse(addr.value) - 1; // 0-based
                line = (int)Math.fmax(0, Math.fmin(line, text_view.line_count - 1));
                pos = new TextPosition(line, 0);
                return true;
                
            case AddressType.CHAR_OFFSET:
                return char_offset_to_position(int.parse(addr.value), text_view, out pos);
                
            case AddressType.PLUS:
                int lines = int.parse(addr.value);
                pos = new TextPosition(
                    (int)Math.fmin(text_view.cursor_line + lines, text_view.line_count - 1),
                    0
                );
                return true;
                
            case AddressType.MINUS:
                int lines = int.parse(addr.value);
                pos = new TextPosition(
                    (int)Math.fmax(text_view.cursor_line - lines, 0),
                    0
                );
                return true;
                
            case AddressType.REGEX:
                return search_pattern(addr.value, addr.reverse, view, out pos);
                
            default:
                pos = new TextPosition(0, 0);
                return false;
        }
    }
    
    // Convert character offset to line/column position
    private bool char_offset_to_position(int offset, AcmeDrawingTextView text_view, out TextPosition pos) {
        int current_offset = 0;
        
        for (int line = 0; line < text_view.line_count; line++) {
            int line_length = text_view.lines[line].length;
            
            if (current_offset + line_length >= offset) {
                pos = new TextPosition(line, offset - current_offset);
                return true;
            }
            
            current_offset += line_length + 1; // +1 for newline
        }
        
        // Offset beyond end of file
        pos = new TextPosition(text_view.line_count - 1, text_view.lines[text_view.line_count - 1].length);
        return true;
    }
    
    // Pattern search implementation
    private bool search_pattern(string pattern, bool reverse, AcmeTextView view, out TextPosition pos) {
        var text_view = view.text_view;
        
        try {
            var regex = new Regex(pattern);
            
            if (reverse) {
                return search_backwards(regex, text_view, out pos);
            } else {
                return search_forwards(regex, text_view, out pos);
            }
        } catch (RegexError e) {
            warning("Regex error: %s", e.message);
            pos = new TextPosition(0, 0);
            return false;
        }
    }
    
    private bool search_forwards(Regex regex, AcmeDrawingTextView text_view, out TextPosition pos) {
        int start_line = text_view.cursor_line;
        int start_col = text_view.cursor_col;
        
        for (int line = start_line; line < text_view.line_count; line++) {
            string text_line = text_view.lines[line];
            int search_start = (line == start_line) ? start_col : 0;
            
            if (search_start < text_line.length) {
                string search_text = text_line.substring(search_start);
                
                MatchInfo match_info;
                if (regex.match(search_text, 0, out match_info)) {
                    int match_start, match_end;
                    if (match_info.fetch_pos(0, out match_start, out match_end)) {
                        pos = new TextPosition(line, search_start + match_start);
                        return true;
                    }
                }
            }
        }
        
        pos = new TextPosition(0, 0);
        return false;
    }
    
    private bool search_backwards(Regex regex, AcmeDrawingTextView text_view, out TextPosition pos) {
        int start_line = text_view.cursor_line;
        int start_col = text_view.cursor_col;
        
        for (int line = start_line; line >= 0; line--) {
            string text_line = text_view.lines[line];
            int search_end = (line == start_line) ? start_col : text_line.length;
            
            if (search_end > 0) {
                string search_text = text_line.substring(0, search_end);
                
                // Find last match in the line
                MatchInfo match_info;
                int last_start = -1;
                
                try {
                    if (regex.match(search_text, 0, out match_info)) {
                        do {
                            int match_start, match_end;
                            if (match_info.fetch_pos(0, out match_start, out match_end)) {
                                last_start = match_start;
                            }
                        } while (match_info.next());
                    }
                } catch (GLib.RegexError re) {
                }
                
                if (last_start >= 0) {
                    pos = new TextPosition(line, last_start);
                    return true;
                }
            }
        }
        
        pos = new TextPosition(0, 0);
        return false;
    }
    
    // Execute operation at a specific range
    private bool execute_operation_at_range(string operation, TextPosition start, TextPosition end, AcmeTextView view) {
        var text_view = view.text_view;
        
        switch (operation) {
            case "d":
                // Delete the range
                return execute_delete_range(start, end, text_view);
                
            case "p":
                // Print (select) - already selected
                text_view.queue_draw();
                return true;
                
            case "c":
                // Change - delete and enter insert mode
                if (execute_delete_range(start, end, text_view)) {
                    // Position cursor where deletion occurred
                    text_view.cursor_line = start.line;
                    text_view.cursor_col = start.col;
                    return true;
                }
                return false;
                
            default:
                if (operation.has_prefix("s/")) {
                    return execute_substitute_range(operation, start, end, text_view);
                } else if (operation.has_prefix("a ")) {
                    // Append after
                    return execute_append_range(operation.substring(2), end, text_view);
                } else if (operation.has_prefix("i ")) {
                    // Insert before
                    return execute_insert_range(operation.substring(2), start, text_view);
                }
                break;
        }
        
        return false;
    }
    
    // Delete text in range
    private bool execute_delete_range(TextPosition start, TextPosition end, AcmeDrawingTextView text_view) {
        // Set selection to the range
        text_view.has_selection = true;
        text_view.selection_start_line = start.line;
        text_view.selection_start_col = start.col;
        text_view.selection_end_line = end.line;
        text_view.selection_end_col = end.col;
        
        // Use the text view's delete selection method
        text_view.delete_selection();
        
        return true;
    }
    
    // Execute substitute on a specific range
    private bool execute_substitute_range(string command, TextPosition start, TextPosition end, AcmeDrawingTextView text_view) {
        // Set selection to the range
        text_view.has_selection = true;
        text_view.selection_start_line = start.line;
        text_view.selection_start_col = start.col;
        text_view.selection_end_line = end.line;
        text_view.selection_end_col = end.col;
        
        // Execute substitute on the selection
        return execute_substitute(command, new AcmeTextView() { text_view = text_view });
    }
    
    // Execute substitute command
    private bool execute_substitute(string command, AcmeTextView view) {
        var text_view = view.text_view;
        
        // Command format: /pattern/replacement/[g]
        if (command.length < 5 || command[0] != '/') return false;
        
        // Find the second delimiter
        int second_delim = -1;
        for (int i = 1; i < command.length; i++) {
            if (command[i] == '/' && command[i-1] != '\\') {
                second_delim = i;
                break;
            }
        }
        
        if (second_delim == -1 || second_delim == command.length - 1) return false;
        
        // Find the third delimiter
        int third_delim = -1;
        for (int i = second_delim + 1; i < command.length; i++) {
            if (command[i] == '/' && command[i-1] != '\\') {
                third_delim = i;
                break;
            }
        }
        
        if (third_delim == -1) third_delim = command.length;
        
        // Extract pattern and replacement
        string pattern = command.substring(1, second_delim - 1);
        string replacement = command.substring(second_delim + 1, third_delim - second_delim - 1);
        
        // Check for global flag
        bool global = (third_delim < command.length - 1 && command[third_delim + 1] == 'g');
        
        // Get selected text or current line
        string text;
        if (text_view.has_selection) {
            text = text_view.get_selected_text();
        } else {
            // Use current line if no selection
            text = text_view.lines[text_view.cursor_line];
        }
        
        try {
            Regex regex = new Regex(pattern);
            string result;
            
            if (global) {
                result = regex.replace(text, text.length, 0, replacement);
            } else {
                result = regex.replace_literal(text, text.length, 0, replacement, 0);
            }
            
            // Replace the text
            if (text_view.has_selection) {
                text_view.delete_selection();
                text_view.insert_text(result);
            } else {
                // Replace entire line
                text_view.lines[text_view.cursor_line] = result;
                text_view.queue_draw();
            }
            
            return true;
        } catch (RegexError e) {
            warning("Regex error: %s", e.message);
            return false;
        }
    }
    
    // Insert text at position
    private bool execute_insert_range(string text, TextPosition pos, AcmeDrawingTextView text_view) {
        text_view.cursor_line = pos.line;
        text_view.cursor_col = pos.col;
        text_view.insert_text(text);
        return true;
    }
    
    // Append text after position
    private bool execute_append_range(string text, TextPosition pos, AcmeDrawingTextView text_view) {
        // Move to end of line if appending
        text_view.cursor_line = pos.line;
        text_view.cursor_col = text_view.lines[pos.line].length;
        text_view.insert_text(text);
        return true;
    }
}