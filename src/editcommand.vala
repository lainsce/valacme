/* editcommand.vala
 * Edit command implementation for ACME Vala
 */

public class AcmeEditCommand : Object {
    // Simplified AddressType enum
    public enum AddressType {
        LINE_NUMBER,    // 5
        DOT,           // .
        DOLLAR,        // $
        REGEX,         // /pattern/ or ?pattern?
        PLUS,          // +n
        MINUS,         // -n
        CHAR_OFFSET,   // #n
        NONE
    }
    
    // Simple Address class
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
    
    // Simple AddressRange class
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
    
    // Simple text position
    public class TextPosition {
        public int line;
        public int col;
        
        public TextPosition(int line, int col) {
            this.line = line;
            this.col = col;
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
    
    // Main execute method - simplified
    public bool execute(string command, AcmeTextView view) {
        var parts = split_address_command(command);
        if (parts.length < 1) return false;
        
        if (parts.length == 1) {
            // No explicit address, check for commands with implicit addresses
            if (command.has_prefix("s/")) {
                return execute_substitute(command.substring(1), view);
            }
            return false;
        }
        
        string address_str = parts[0];
        string operation = parts[1];
        
        // Parse and evaluate the address
        var range = parse_address_range(address_str);
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
    
    // Simplified address parsing - much cleaner
    private AddressRange? parse_address_range(string address_text) {
        var range = new AddressRange();
        
        // Simple parsing - look for comma or semicolon to split range
        int separator_pos = -1;
        char separator = ',';
        
        // Find range separator (not inside regex)
        bool in_regex = false;
        char regex_char = '\0';
        
        for (int i = 0; i < address_text.length; i++) {
            char c = address_text[i];
            
            if (c == '/' || c == '?') {
                if (!in_regex) {
                    in_regex = true;
                    regex_char = c;
                } else if (c == regex_char) {
                    in_regex = false;
                }
            } else if (!in_regex && (c == ',' || c == ';')) {
                separator_pos = i;
                separator = c;
                break;
            }
        }
        
        if (separator_pos > 0) {
            // Range address
            string start_addr = address_text.substring(0, separator_pos).strip();
            string end_addr = address_text.substring(separator_pos + 1).strip();
            
            range.start = parse_single_address(start_addr);
            range.end = parse_single_address(end_addr);
            range.operator = separator.to_string();
        } else {
            // Single address
            range.start = parse_single_address(address_text.strip());
            range.end = null;
        }
        
        return range;
    }
    
    // Simplified single address parsing
    private Address? parse_single_address(string addr) {
        if (addr == "") return null;
        
        char first = addr[0];
        
        switch (first) {
            case '.':
                return new Address(AddressType.DOT);
                
            case '$':
                return new Address(AddressType.DOLLAR);
                
            case '#':
                string num = addr.substring(1);
                return new Address(AddressType.CHAR_OFFSET, num);
                
            case '/':
                if (addr.length >= 2 && addr[addr.length - 1] == '/') {
                    string pattern = addr.substring(1, addr.length - 2);
                    return new Address(AddressType.REGEX, pattern, false);
                }
                break;
                
            case '?':
                if (addr.length >= 2 && addr[addr.length - 1] == '?') {
                    string pattern = addr.substring(1, addr.length - 2);
                    return new Address(AddressType.REGEX, pattern, true);
                }
                break;
                
            case '+':
                string num = addr.length > 1 ? addr.substring(1) : "1";
                return new Address(AddressType.PLUS, num);
                
            case '-':
                string num = addr.length > 1 ? addr.substring(1) : "1";
                return new Address(AddressType.MINUS, num);
                
            default:
                if (first.isdigit()) {
                    return new Address(AddressType.LINE_NUMBER, addr);
                }
                break;
        }
        
        return null;
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
    
    // Simplified range evaluation
    private bool evaluate_range(AddressRange range, AcmeTextView view, 
                               out TextPosition start, out TextPosition end) {
        var text_view = view.text_view;
        
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
                end = new TextPosition(0, 0);
                return false;
            }
        }
        
        if (range.end == null) {
            // Single address - set end to start
            end = new TextPosition(start.line, start.col);
        } else {
            // Handle semicolon operator (change context)
            if (range.operator == ";") {
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
    
    // Simplified address evaluation
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
                int line = int.parse(addr.value) - 1; // Convert to 0-based
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
    
    // Pattern search - simplified
    private bool search_pattern(string pattern, bool reverse, AcmeTextView view, out TextPosition pos) {
        var text_view = view.text_view;
        
        try {
            var regex = new Regex(pattern);
            return reverse ? 
                search_backwards(regex, text_view, out pos) : 
                search_forwards(regex, text_view, out pos);
        } catch (RegexError e) {
            warning("Regex error: %s", e.message);
            pos = new TextPosition(0, 0);
            return false;
        }
    }
    
    private bool search_forwards(Regex regex, AcmeDrawingTextView text_view, out TextPosition pos) {
        int start_line = text_view.cursor_line;
        
        for (int line = start_line; line < text_view.line_count; line++) {
            string text_line = text_view.lines[line];
            int search_start = (line == start_line) ? text_view.cursor_col : 0;
            
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
        
        for (int line = start_line; line >= 0; line--) {
            string text_line = text_view.lines[line];
            int search_end = (line == start_line) ? text_view.cursor_col : text_line.length;
            
            if (search_end > 0) {
                string search_text = text_line.substring(0, search_end);
                
                // Find last match in the line
                MatchInfo match_info;
                int last_start = -1;
                
                if (regex.match(search_text, 0, out match_info)) {
                    do {
                        int match_start, match_end;
                        if (match_info.fetch_pos(0, out match_start, out match_end)) {
                            last_start = match_start;
                        }
                    } while (match_info.next());
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
    
    // Execute operation at a specific range - simplified dispatch
    private bool execute_operation_at_range(string operation, TextPosition start, TextPosition end, AcmeTextView view) {
        var text_view = view.text_view;
        
        switch (operation) {
            case "d":
                return execute_delete_range(start, end, text_view);
                
            case "p":
                // Print (select) - already selected
                text_view.queue_draw();
                return true;
                
            case "c":
                // Change - delete and enter insert mode
                if (execute_delete_range(start, end, text_view)) {
                    text_view.cursor_line = start.line;
                    text_view.cursor_col = start.col;
                    return true;
                }
                return false;
                
            default:
                if (operation.has_prefix("s/")) {
                    return execute_substitute_range(operation, start, end, text_view);
                } else if (operation.has_prefix("a ")) {
                    return execute_append_range(operation.substring(2), end, text_view);
                } else if (operation.has_prefix("i ")) {
                    return execute_insert_range(operation.substring(2), start, text_view);
                }
                break;
        }
        
        return false;
    }
    
    // Simplified operation implementations
    private bool execute_delete_range(TextPosition start, TextPosition end, AcmeDrawingTextView text_view) {
        text_view.has_selection = true;
        text_view.selection_start_line = start.line;
        text_view.selection_start_col = start.col;
        text_view.selection_end_line = end.line;
        text_view.selection_end_col = end.col;
        
        text_view.delete_selection();
        return true;
    }
    
    private bool execute_substitute_range(string command, TextPosition start, TextPosition end, AcmeDrawingTextView text_view) {
        text_view.has_selection = true;
        text_view.selection_start_line = start.line;
        text_view.selection_start_col = start.col;
        text_view.selection_end_line = end.line;
        text_view.selection_end_col = end.col;
        
        return execute_substitute(command, new AcmeTextView() { text_view = text_view });
    }
    
    // Simplified substitute command
    private bool execute_substitute(string command, AcmeTextView view) {
        var text_view = view.text_view;
        
        if (command.length < 5 || command[0] != '/') return false;
        
        // Simple parsing - find delimiters
        var parts = command.split("/");
        if (parts.length < 3) return false;
        
        string pattern = parts[1];
        string replacement = parts[2];
        bool global = (parts.length > 3 && parts[3].contains("g"));
        
        // Get text to operate on
        string text = text_view.has_selection ? 
            text_view.get_selected_text() : 
            text_view.lines[text_view.cursor_line];
        
        try {
            Regex regex = new Regex(pattern);
            string result = global ? 
                regex.replace(text, text.length, 0, replacement) :
                regex.replace_literal(text, text.length, 0, replacement, 0);
            
            // Replace the text
            if (text_view.has_selection) {
                text_view.delete_selection();
                text_view.insert_text(result);
            } else {
                text_view.lines[text_view.cursor_line] = result;
                text_view.queue_draw();
            }
            
            return true;
        } catch (RegexError e) {
            warning("Regex error: %s", e.message);
            return false;
        }
    }
    
    private bool execute_insert_range(string text, TextPosition pos, AcmeDrawingTextView text_view) {
        text_view.cursor_line = pos.line;
        text_view.cursor_col = pos.col;
        text_view.insert_text(text);
        return true;
    }
    
    private bool execute_append_range(string text, TextPosition pos, AcmeDrawingTextView text_view) {
        text_view.cursor_line = pos.line;
        text_view.cursor_col = text_view.lines[pos.line].length;
        text_view.insert_text(text);
        return true;
    }
}