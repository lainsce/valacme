/* plumber.vala
 * Simple plumbing system for ACME Vala
 */

public enum PlumbingType {
    UNKNOWN,
    FILE,
    DIRECTORY,
    URL,
    EMAIL,
    IMAGE,
    FILE_LINE,
    FILE_LINE_COL,
    COMPILER_ERROR,
    STACK_TRACE,
    GREP_RESULT,
    GIT_DIFF
}

public class AcmePlumber : Object {
    private static AcmePlumber? instance;
    
    // Pattern definition for data-driven approach - much cleaner
    private struct PatternDef {
        string name;
        string pattern;
        PlumbingType type;
        RegexCompileFlags flags;
    }
    
    // All patterns in one place - easy to maintain and extend
    private static PatternDef[] PATTERNS = {
        // Development patterns (check first - more specific)
        {"compiler_error", """^([^:]+):(\d+):(\d+):\s*(error|warning):""", PlumbingType.COMPILER_ERROR, 0},
        {"stack_trace", """^\s*at\s+.*\((.*):(\d+)\)""", PlumbingType.STACK_TRACE, 0},
        {"grep_result", """^([^:]+):(\d+):""", PlumbingType.GREP_RESULT, 0},
        {"git_diff", """^@@\s+-\d+,?\d*\s+\+(\d+),?\d*\s+@@""", PlumbingType.GIT_DIFF, 0},
        {"file_line_col", """^(.+):(\d+):(\d+)$""", PlumbingType.FILE_LINE_COL, 0},
        {"file_line", """^(.+):(\d+)$""", PlumbingType.FILE_LINE, 0},
        
        // Basic patterns
        {"url", """^(https?|ftp)://\S+$""", PlumbingType.URL, 0},
        {"email", """^[\w\.-]+@[\w\.-]+\.\w+$""", PlumbingType.EMAIL, 0},
        {"image", """\.(?:jpg|jpeg|png|gif|bmp|svg)$""", PlumbingType.IMAGE, RegexCompileFlags.CASELESS}
    };
    
    private HashTable<string, Regex> compiled_patterns;
    
    private AcmePlumber() {
        compiled_patterns = new HashTable<string, Regex>(str_hash, str_equal);
        compile_patterns();
    }
    
    // Compile all patterns at startup
    private void compile_patterns() {
        foreach (var def in PATTERNS) {
            try {
                var regex = new Regex(def.pattern, def.flags);
                compiled_patterns.insert(def.name, regex);
            } catch (RegexError e) {
                warning("Failed to compile pattern %s: %s", def.name, e.message);
            }
        }
    }
    
    public static AcmePlumber get_instance() {
        if (instance == null) {
            instance = new AcmePlumber();
        }
        return instance;
    }
    
    // Simplified pattern analysis - data-driven
    public PlumbingType analyze_text(string text) {
        // Check patterns in order of specificity (development patterns first)
        foreach (var def in PATTERNS) {
            var regex = compiled_patterns.lookup(def.name);
            if (regex != null && regex.match(text)) {
                return def.type;
            }
        }
        
        // Check if it looks like a file using simple heuristics
        if (looks_like_file(text)) {
            if (compiled_patterns.lookup("image").match(text)) {
                return PlumbingType.IMAGE;
            } else if (is_directory(text)) {
                return PlumbingType.DIRECTORY;
            } else {
                return PlumbingType.FILE;
            }
        }
        
        return PlumbingType.UNKNOWN;
    }
    
    // Simple heuristic for file paths
    private bool looks_like_file(string text) {
        // Skip URLs and emails
        if (text.contains("://") || text.contains("@")) return false;
        
        // Too long is probably not a file path
        if (text.length > 256) return false;
        
        // Too many spaces suggests it's not a path
        int spaces = 0;
        for (int i = 0; i < text.length; i++) {
            if (text[i] == ' ') spaces++;
        }
        if (spaces > 2) return false;
        
        // Has file-like characteristics
        return text.contains("/") || text.contains(".") || text.has_suffix("/");
    }
    
    private bool is_directory(string path) {
        var file = File.new_for_path(path);
        try {
            var info = file.query_info("standard::type", FileQueryInfoFlags.NONE);
            return info.get_file_type() == FileType.DIRECTORY;
        } catch {
            return path.has_suffix("/");
        }
    }
    
    // Simplified plumbing with generic handlers
    public bool plumb_text(string text, AcmeTextView? source_view) {
        var type = analyze_text(text);
        
        switch (type) {
            case PlumbingType.URL:
            case PlumbingType.EMAIL:
            case PlumbingType.IMAGE:
                return open_external(text, type);
                
            case PlumbingType.FILE:
            case PlumbingType.DIRECTORY:
                return open_in_acme(text, source_view, type);
                
            case PlumbingType.FILE_LINE:
            case PlumbingType.FILE_LINE_COL:
            case PlumbingType.COMPILER_ERROR:
            case PlumbingType.STACK_TRACE:
            case PlumbingType.GREP_RESULT:
                return open_with_location(text, source_view, type);
                
            case PlumbingType.GIT_DIFF:
                return handle_git_diff(text, source_view);
                
            default:
                return false;
        }
    }
    
    // Generic external opener - handles URLs, emails, images
    private bool open_external(string text, PlumbingType type) {
        string command = "";
        
        switch (type) {
            case PlumbingType.URL:
                command = "xdg-open " + Shell.quote(text);
                break;
            case PlumbingType.EMAIL:
                command = "xdg-open mailto:" + text;
                break;
            case PlumbingType.IMAGE:
                command = "xdg-open " + Shell.quote(text);
                break;
            default:
                return false;
        }
        
        try {
            Process.spawn_command_line_async(command);
            return true;
        } catch (Error e) {
            warning("Failed to open %s: %s", text, e.message);
            return false;
        }
    }
    
    // Generic file opener for Acme
    private bool open_in_acme(string path, AcmeTextView? source_view, PlumbingType type) {
        var window = AcmeUIHelper.find_root_window(source_view);
        if (window == null) return false;
        
        var target_column = find_target_column(source_view, window);
        var new_view = new AcmeTextView();
        target_column.add_text_view(new_view);
        
        string resolved_path = resolve_path(path, source_view);
        new_view.execute_get(resolved_path);
        
        if (type == PlumbingType.DIRECTORY) {
            new_view.ensure_directory_tagline();
        }
        
        return true;
    }
    
    // Generic location-based opener
    private bool open_with_location(string text, AcmeTextView? source_view, PlumbingType type) {
        var location = extract_location(text, type);
        if (location == null) return false;
        
        if (!open_in_acme(location.filepath, source_view, PlumbingType.FILE)) {
            return false;
        }
        
        // Navigate to location
        var window = AcmeUIHelper.find_root_window(source_view);
        if (window == null) return false;
        
        var views = window.get_all_text_views();
        foreach (var view in views) {
            if (view.get_filename() == resolve_path(location.filepath, source_view)) {
                view.scroll_to_line_column(location.line, location.column);
                return true;
            }
        }
        
        return false;
    }
    
    // Helper class for location data
    private class LocationInfo {
        public string filepath;
        public int line;
        public int column;
        
        public LocationInfo(string path, int l, int c = 0) {
            filepath = path;
            line = l;
            column = c;
        }
    }
    
    // Extract location info from different pattern types - unified approach
    private LocationInfo? extract_location(string text, PlumbingType type) {
        MatchInfo match;
        
        switch (type) {
            case PlumbingType.FILE_LINE:
                if (compiled_patterns.lookup("file_line").match(text, 0, out match)) {
                    return new LocationInfo(match.fetch(1), int.parse(match.fetch(2)));
                }
                break;
                
            case PlumbingType.FILE_LINE_COL:
                if (compiled_patterns.lookup("file_line_col").match(text, 0, out match)) {
                    return new LocationInfo(match.fetch(1), int.parse(match.fetch(2)), int.parse(match.fetch(3)));
                }
                break;
                
            case PlumbingType.COMPILER_ERROR:
                if (compiled_patterns.lookup("compiler_error").match(text, 0, out match)) {
                    return new LocationInfo(match.fetch(1), int.parse(match.fetch(2)), int.parse(match.fetch(3)));
                }
                break;
                
            case PlumbingType.STACK_TRACE:
                if (compiled_patterns.lookup("stack_trace").match(text, 0, out match)) {
                    return new LocationInfo(match.fetch(1), int.parse(match.fetch(2)));
                }
                break;
                
            case PlumbingType.GREP_RESULT:
                if (compiled_patterns.lookup("grep_result").match(text, 0, out match)) {
                    return new LocationInfo(match.fetch(1), int.parse(match.fetch(2)));
                }
                break;
        }
        
        return null;
    }
    
    // Git diff handler - special case
    private bool handle_git_diff(string text, AcmeTextView? source_view) {
        MatchInfo match;
        if (!compiled_patterns.lookup("git_diff").match(text, 0, out match)) return false;
        
        int line = int.parse(match.fetch(1));
        
        // For git diff, we need the file context - look for --- or +++ lines
        var window = source_view?.get_root() as AcmeWindow;
        if (window != null) {
            var view = window.get_errors_view();
            if (view != null) {
                string errors_text = view.text_view.get_text();
                
                // Look for recent file markers
                string[] lines = errors_text.split("\n");
                string? current_file = null;
                
                for (int i = lines.length - 1; i >= 0; i--) {
                    if (lines[i] == text) break;
                    
                    if (lines[i].has_prefix("--- a/") || lines[i].has_prefix("+++ b/")) {
                        string marker = lines[i];
                        if (marker.has_prefix("--- a/")) {
                            current_file = marker.substring(6);
                        } else if (marker.has_prefix("+++ b/")) {
                            current_file = marker.substring(6);
                        }
                        break;
                    }
                }
                
                if (current_file != null) {
                    return open_with_location(current_file + ":" + line.to_string(), source_view, PlumbingType.FILE_LINE);
                }
            }
        }
        return false;
    }
    
    // Helper methods
    private AcmeColumn find_target_column(AcmeTextView? source_view, AcmeWindow window) {
        if (source_view != null) {
            var column = AcmeUIHelper.find_parent_of_type<AcmeColumn>(source_view);
            if (column != null) return column;
        }
        return window.get_last_column();
    }
    
    private string resolve_path(string path, AcmeTextView? source_view) {
        if (Path.is_absolute(path)) return path;
        
        // Try relative to source file's directory
        if (source_view != null) {
            string source_file = source_view.get_filename();
            if (source_file != "Untitled" && source_file != "+Errors") {
                string dir = Path.get_dirname(source_file);
                string full_path = Path.build_filename(dir, path);
                if (File.new_for_path(full_path).query_exists()) {
                    return full_path;
                }
            }
        }
        
        // Fall back to current directory
        return path;
    }
}