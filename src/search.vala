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
    
    // Unified search result - eliminates duplication
    private struct SearchMatch {
        int line;
        int start_col;
        int end_col;
        
        public SearchMatch(int l, int s, int e) {
            line = l; 
            start_col = s; 
            end_col = e;
        }
    }
    
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
    
    // Unified search method - eliminates duplication between regex and plain text
    public bool search_in_view(AcmeTextView view, bool forward = true) {
        current_view = view;
        string text = view.text_view.get_text();
        string[] lines = text.split("\n");
        
        int start_line = get_search_start_line(view, forward);
        var match = find_next_match(lines, start_line, forward);
        
        if (match != null) {
            select_match(view, match);
            return true;
        }
        
        return false;
    }
    
    // Get appropriate starting line for search
    private int get_search_start_line(AcmeTextView view, bool forward) {
        if (view.text_view.has_selection) {
            return forward ? 
                (int)Math.fmax(view.text_view.selection_start_line, view.text_view.selection_end_line) :
                (int)Math.fmin(view.text_view.selection_start_line, view.text_view.selection_end_line);
        }
        return view.text_view.cursor_line;
    }
    
    // Single method handles both regex and plain text - no duplication
    private SearchMatch? find_next_match(string[] lines, int start_line, bool forward) {
        int end_line = forward ? lines.length - 1 : 0;
        int increment = forward ? 1 : -1;
        
        // Search through lines
        for (int line = start_line; 
             forward ? (line <= end_line) : (line >= end_line); 
             line += increment) {
            
            var match = search_in_line(lines[line], line);
            if (match != null) {
                return match;
            }
        }
        
        return null;
    }
    
    // Unified line search - handles both regex and plain text in one place
    private SearchMatch? search_in_line(string line, int line_num) {
        if (use_regex) {
            return search_regex_in_line(line, line_num);
        } else {
            return search_text_in_line(line, line_num);
        }
    }
    
    // Regex search in a single line
    private SearchMatch? search_regex_in_line(string line, int line_num) {
        try {
            var regex = new Regex(search_pattern, 
                case_sensitive ? 0 : RegexCompileFlags.CASELESS);
            
            MatchInfo match_info;
            if (regex.match(line, 0, out match_info)) {
                int start_pos, end_pos;
                if (match_info.fetch_pos(0, out start_pos, out end_pos)) {
                    return SearchMatch(line_num, start_pos, end_pos);
                }
            }
        } catch (RegexError e) {
            warning("Regex error: %s", e.message);
        }
        
        return null;
    }
    
    // Plain text search in a single line
    private SearchMatch? search_text_in_line(string line, int line_num) {
        string search_line = case_sensitive ? line : line.down();
        string search_term = case_sensitive ? search_pattern : search_pattern.down();
        
        int pos = search_line.index_of(search_term);
        if (pos != -1) {
            return SearchMatch(line_num, pos, pos + search_pattern.length);
        }
        
        return null;
    }
    
    // Apply the search match to the text view
    private void select_match(AcmeTextView view, SearchMatch match) {
        view.text_view.has_selection = true;
        view.text_view.selection_start_line = match.line;
        view.text_view.selection_start_col = match.start_col;
        view.text_view.selection_end_line = match.line;
        view.text_view.selection_end_col = match.end_col;
        
        // Position cursor at end of match
        view.text_view.cursor_line = match.line;
        view.text_view.cursor_col = match.end_col;
        
        // Ensure match is visible
        view.text_view.ensure_cursor_visible();
        view.text_view.queue_draw();
    }
    
    // Simplified search all - reuses search_in_view instead of duplicating logic
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