/* search.vala
 * Search implementation
 */

public class AcmeSearch : Object {
    private static AcmeSearch? instance;
    
    // Current search parameters
    private string search_pattern = "";
    private bool use_regex = false;
    private bool case_sensitive = false;
    
    // Current search state
    private weak AcmeTextView? current_view = null;
    
    private AcmeSearch() {
    }
    
    public static AcmeSearch get_instance() {
        if (instance == null) {
            instance = new AcmeSearch();
        }
        return instance;
    }
    
    // Parse an Acme-style search pattern
    public void parse_search_pattern(string pattern) {
        // Check if it's a regex pattern (enclosed in / / )
        if (pattern.length >= 2 && pattern[0] == '/' && pattern[pattern.length - 1] == '/') {
            use_regex = true;
            search_pattern = pattern.substring(1, pattern.length - 2);
        } else {
            use_regex = false;
            search_pattern = pattern;
        }
    }
    
    // Search in the given text view
    public bool search_in_view(AcmeTextView view, bool forward = true) {
        current_view = view;
        
        // Get text and current selection from the drawing text view
        string text = view.text_view.get_text();
        int cursor_pos;
        
        // Get current cursor position for starting search
        if (forward) {
            // For forward search, start from cursor or end of selection
            if (view.text_view.has_selection) {
                // Get end of selection
                cursor_pos = (int)Math.fmax(
                    view.text_view.selection_start_line * 1000 + view.text_view.selection_start_col,
                    view.text_view.selection_end_line * 1000 + view.text_view.selection_end_col
                );
            } else {
                cursor_pos = view.text_view.cursor_line * 1000 + view.text_view.cursor_col;
            }
        } else {
            // For backward search, start from cursor or start of selection
            if (view.text_view.has_selection) {
                // Get start of selection
                cursor_pos = (int)Math.fmin(
                    view.text_view.selection_start_line * 1000 + view.text_view.selection_start_col,
                    view.text_view.selection_end_line * 1000 + view.text_view.selection_end_col
                );
            } else {
                cursor_pos = view.text_view.cursor_line * 1000 + view.text_view.cursor_col;
            }
        }
        
        // Split search area into lines
        string[] lines = text.split("\n");
        
        // Search based on mode (regex or plain text)
        if (use_regex) {
            try {
                Regex regex = new Regex(search_pattern, 
                    case_sensitive ? 0 : RegexCompileFlags.CASELESS);
                
                int start_line = cursor_pos / 1000;
                int end_line = forward ? lines.length - 1 : 0;
                int increment = forward ? 1 : -1;
                
                // Search through lines
                for (int i = start_line; forward ? (i <= end_line) : (i >= end_line); i += increment) {
                    string line = lines[i];
                    
                    // For first line, start from cursor position
                    string search_text = line;
                    int start_col = 0;
                    
                    if (i == start_line) {
                        start_col = cursor_pos % 1000;
                        if (forward) {
                            search_text = line.substring(start_col);
                        } else {
                            search_text = line.substring(0, start_col);
                        }
                    }
                    
                    // Search in the line
                    MatchInfo match_info;
                    if (regex.match(search_text, 0, out match_info)) {
                        int start_pos, end_pos;
                        if (match_info.fetch_pos(0, out start_pos, out end_pos)) {
                            // Convert string positions to line and column
                            int match_start_col = start_col + start_pos;
                            int match_end_col = start_col + end_pos;
                            
                            // Select the match in the text view
                            view.text_view.has_selection = true;
                            view.text_view.selection_start_line = i;
                            view.text_view.selection_start_col = match_start_col;
                            view.text_view.selection_end_line = i;
                            view.text_view.selection_end_col = match_end_col;
                            
                            // Position cursor at end of match
                            view.text_view.cursor_line = i;
                            view.text_view.cursor_col = match_end_col;
                            
                            // Ensure match is visible
                            view.text_view.ensure_cursor_visible();
                            view.text_view.queue_draw();
                            
                            return true;
                        }
                    }
                }
            } catch (RegexError e) {
                warning("Regex error: %s", e.message);
                return false;
            }
        } else {
            // Plain text search
            int start_line = cursor_pos / 1000;
            int end_line = forward ? lines.length - 1 : 0;
            int increment = forward ? 1 : -1;
            
            // Search through lines
            for (int i = start_line; forward ? (i <= end_line) : (i >= end_line); i += increment) {
                string line = lines[i];
                
                // For first line, start from cursor position
                int start_col = 0;
                
                if (i == start_line) {
                    start_col = cursor_pos % 1000;
                    if (forward) {
                        line = line.substring(start_col);
                    } else {
                        line = line.substring(0, start_col);
                    }
                }
                
                // Search in the line
                int match_pos = -1;
                if (forward) {
                    match_pos = line.index_of(search_pattern);
                } else {
                    // For backward search, find the last occurrence
                    int pos = 0;
                    int last_pos = -1;
                    while ((pos = line.index_of(search_pattern, pos)) != -1) {
                        last_pos = pos;
                        pos += search_pattern.length;
                    }
                    match_pos = last_pos;
                }
                
                if (match_pos != -1) {
                    // Convert string positions to line and column
                    int match_start_col = start_col + match_pos;
                    int match_end_col = match_start_col + search_pattern.length;
                    
                    // Select the match in the text view
                    view.text_view.has_selection = true;
                    view.text_view.selection_start_line = i;
                    view.text_view.selection_start_col = match_start_col;
                    view.text_view.selection_end_line = i;
                    view.text_view.selection_end_col = match_end_col;
                    
                    // Position cursor at end of match
                    view.text_view.cursor_line = i;
                    view.text_view.cursor_col = match_end_col;
                    
                    // Ensure match is visible
                    view.text_view.ensure_cursor_visible();
                    view.text_view.queue_draw();
                    
                    return true;
                }
            }
        }
        
        return false;
    }
    
    // Search in all windows
    public bool search_all(bool forward = true) {
        // Get the active window
        var window = current_view != null ? 
            current_view.get_root() as AcmeWindow : null;
            
        if (window == null) return false;
        
        // Start with the current text view if we have one
        if (current_view != null) {
            if (search_in_view(current_view, forward)) {
                return true;
            }
        }
        
        // Otherwise search all text views
        var views = window.get_all_text_views();
        foreach (var view in views) {
            if (view == current_view) continue; // Skip the current view
            
            if (search_in_view(view, forward)) {
                // Found a match in another view, switch to it
                view.focus_in();
                return true;
            }
        }
        
        return false;
    }
    
    // Execute the Look command
    public bool execute_look(string pattern, AcmeTextView? view) {
        if (view == null) return false;
        
        parse_search_pattern(pattern);
        current_view = view;
        
        return search_in_view(view);
    }
}