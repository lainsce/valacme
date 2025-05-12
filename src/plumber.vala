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
    
    // Simple regex patterns
    private Regex url_pattern;
    private Regex email_pattern;
    private Regex file_line_pattern;
    private Regex file_line_col_pattern;
    private Regex image_pattern;
    private Regex compiler_error_pattern;
    private Regex stack_trace_pattern;
    private Regex grep_result_pattern;
    private Regex git_diff_pattern;
    
    private AcmePlumber() {
        try {
            // Basic patterns
            url_pattern = new Regex("""^(https?|ftp)://\S+$""");
            email_pattern = new Regex("""^[\w\.-]+@[\w\.-]+\.\w+$""");
            image_pattern = new Regex("""\.(?:jpg|jpeg|png|gif|bmp|svg)$""", RegexCompileFlags.CASELESS);
            
            // Development patterns
            file_line_pattern = new Regex("""^(.+):(\d+)$""");
            file_line_col_pattern = new Regex("""^(.+):(\d+):(\d+)$""");
            compiler_error_pattern = new Regex("""^([^:]+):(\d+):(\d+):\s*(error|warning):""");
            stack_trace_pattern = new Regex("""^\s*at\s+.*\((.*):(\d+)\)""");
            grep_result_pattern = new Regex("""^([^:]+):(\d+):""");
            git_diff_pattern = new Regex("""^@@\s+-\d+,?\d*\s+\+(\d+),?\d*\s+@@""");
        } catch (RegexError e) {
            warning("Failed to compile plumbing patterns: %s", e.message);
        }
    }
    
    public static AcmePlumber get_instance() {
        if (instance == null) {
            instance = new AcmePlumber();
        }
        return instance;
    }
    
    // Simple pattern analysis
    public PlumbingType analyze_text(string text) {
        // Check for development patterns first (more specific)
        if (compiler_error_pattern.match(text)) {
            return PlumbingType.COMPILER_ERROR;
        } else if (stack_trace_pattern.match(text)) {
            return PlumbingType.STACK_TRACE;
        } else if (grep_result_pattern.match(text)) {
            return PlumbingType.GREP_RESULT;
        } else if (git_diff_pattern.match(text)) {
            return PlumbingType.GIT_DIFF;
        } else if (file_line_col_pattern.match(text)) {
            return PlumbingType.FILE_LINE_COL;
        } else if (file_line_pattern.match(text)) {
            return PlumbingType.FILE_LINE;
        }
        
        // Check for basic patterns
        else if (url_pattern.match(text)) {
            return PlumbingType.URL;
        } else if (email_pattern.match(text)) {
            return PlumbingType.EMAIL;
        } else if (looks_like_file(text)) {
            if (image_pattern.match(text)) {
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
    
    // Simple plumbing actions
    public bool plumb_text(string text, AcmeTextView? source_view) {
        var type = analyze_text(text);
        
        switch (type) {
            case PlumbingType.URL:
                return open_url(text);
                
            case PlumbingType.EMAIL:
                return open_email(text);
                
            case PlumbingType.IMAGE:
                return open_image(text);
                
            case PlumbingType.FILE:
                return open_file(text, source_view);
                
            case PlumbingType.DIRECTORY:
                return open_directory(text, source_view);
                
            case PlumbingType.FILE_LINE:
                return open_file_at_line(text, source_view);
                
            case PlumbingType.FILE_LINE_COL:
                return open_file_at_line_col(text, source_view);
                
            case PlumbingType.COMPILER_ERROR:
                return handle_compiler_error(text, source_view);
                
            case PlumbingType.STACK_TRACE:
                return handle_stack_trace(text, source_view);
                
            case PlumbingType.GREP_RESULT:
                return handle_grep_result(text, source_view);
                
            case PlumbingType.GIT_DIFF:
                return handle_git_diff(text, source_view);
                
            default:
                return false;
        }
    }
    
    // Basic handlers
    private bool open_url(string url) {
        try {
            Process.spawn_command_line_async("xdg-open " + Shell.quote(url));
            return true;
        } catch (Error e) {
            warning("Failed to open URL: %s", e.message);
            return false;
        }
    }
    
    private bool open_email(string email) {
        try {
            Process.spawn_command_line_async("xdg-open mailto:" + email);
            return true;
        } catch (Error e) {
            warning("Failed to open email: %s", e.message);
            return false;
        }
    }
    
    private bool open_image(string path) {
        try {
            Process.spawn_command_line_async("xdg-open " + Shell.quote(path));
            return true;
        } catch (Error e) {
            warning("Failed to open image: %s", e.message);
            return false;
        }
    }
    
    private bool open_file(string path, AcmeTextView? source_view) {
        return open_file_in_acme(resolve_path(path, source_view), source_view);
    }
    
    private bool open_directory(string path, AcmeTextView? source_view) {
        return open_directory_in_acme(resolve_path(path, source_view), source_view);
    }
    
    // Development-specific handlers
    private bool open_file_at_line(string text, AcmeTextView? source_view) {
        MatchInfo match;
        if (!file_line_pattern.match(text, 0, out match)) return false;
        
        string filepath = match.fetch(1);
        int line = int.parse(match.fetch(2));
        
        return open_file_with_navigation(resolve_path(filepath, source_view), line, 0, source_view);
    }
    
    private bool open_file_at_line_col(string text, AcmeTextView? source_view) {
        MatchInfo match;
        if (!file_line_col_pattern.match(text, 0, out match)) return false;
        
        string filepath = match.fetch(1);
        int line = int.parse(match.fetch(2));
        int col = int.parse(match.fetch(3));
        
        return open_file_with_navigation(resolve_path(filepath, source_view), line, col, source_view);
    }
    
    private bool handle_compiler_error(string text, AcmeTextView? source_view) {
        MatchInfo match;
        if (!compiler_error_pattern.match(text, 0, out match)) return false;
        
        string filepath = match.fetch(1);
        int line = int.parse(match.fetch(2));
        int col = int.parse(match.fetch(3));
        
        return open_file_with_navigation(resolve_path(filepath, source_view), line, col, source_view);
    }
    
    private bool handle_stack_trace(string text, AcmeTextView? source_view) {
        MatchInfo match;
        if (!stack_trace_pattern.match(text, 0, out match)) return false;
        
        string filepath = match.fetch(1);
        int line = int.parse(match.fetch(2));
        
        return open_file_with_navigation(resolve_path(filepath, source_view), line, 0, source_view);
    }
    
    private bool handle_grep_result(string text, AcmeTextView? source_view) {
        MatchInfo match;
        if (!grep_result_pattern.match(text, 0, out match)) return false;
        
        string filepath = match.fetch(1);
        int line = int.parse(match.fetch(2));
        
        return open_file_with_navigation(resolve_path(filepath, source_view), line, 0, source_view);
    }
    
    private bool handle_git_diff(string text, AcmeTextView? source_view) {
        MatchInfo match;
        if (!git_diff_pattern.match(text, 0, out match)) return false;
        
        int line = int.parse(match.fetch(1));
        
        // For git diff, we need the file context - look for --- or +++ lines
        // This is a simplified approach
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
                    return open_file_with_navigation(resolve_path(current_file, source_view), line, 0, source_view);
                }
            }
        }
        return false;
    }
    
    // Helper functions
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
    
    private bool open_file_in_acme(string filepath, AcmeTextView? source_view) {
        var window = AcmeUIHelper.find_root_window(source_view);
        if (window == null) return false;
        
        // Find appropriate column (prefer source view's column)
        AcmeColumn? target_column = null;
        if (source_view != null) {
            target_column = AcmeUIHelper.find_parent_of_type<AcmeColumn>(source_view);
        }
        if (target_column == null) {
            // Use last column as fallback
            var column = window.get_last_column();
            target_column = column;
        }
        
        // Create new text view
        var new_view = new AcmeTextView();
        target_column.add_text_view(new_view);
        new_view.execute_get(filepath);
        
        return true;
    }
    
    private bool open_directory_in_acme(string dirpath, AcmeTextView? source_view) {
        var window = AcmeUIHelper.find_root_window(source_view);
        if (window == null) return false;
        
        AcmeColumn? target_column = null;
        if (source_view != null) {
            target_column = AcmeUIHelper.find_parent_of_type<AcmeColumn>(source_view);
        }
        if (target_column == null) {
            var column = window.get_last_column();
            target_column = column;
        }
        
        var new_view = new AcmeTextView();
        target_column.add_text_view(new_view);
        new_view.execute_get(dirpath);
        new_view.ensure_directory_tagline();
        
        return true;
    }
    
    private bool open_file_with_navigation(string filepath, int line, int col, AcmeTextView? source_view) {
        if (!open_file_in_acme(filepath, source_view)) return false;
        
        // Find the newly opened file and navigate to the position
        var window = AcmeUIHelper.find_root_window(source_view);
        if (window == null) return false;
        
        var text_views = window.get_all_text_views();
        foreach (var view in text_views) {
            if (view.get_filename() == filepath) {
                view.scroll_to_line_column(line, col);
                return true;
            }
        }
        
        return false;
    }
}