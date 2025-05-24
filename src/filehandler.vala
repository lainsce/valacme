/* filehandler.vala
 * File operations for ACME Vala
 */

public class AcmeFileHandler : Object {
    
    /**
     * Load file content into a text buffer
     */
    public static bool load_file(string path, Gtk.TextBuffer buffer, out string error_message) {
        error_message = "";
        
        try {
            var file = File.new_for_path(path);
            if (!file.query_exists()) {
                error_message = "File does not exist: " + path;
                return false;
            }
            
            uint8[] contents;
            string etag_out;
            file.load_contents(null, out contents, out etag_out);
            
            string text = (string) contents;
            buffer.set_text(text, text.length);
            
            return true;
        } catch (Error e) {
            error_message = "Error loading file: " + e.message;
            return false;
        }
    }
    
    /**
     * Load file content into an AcmeDrawingTextView
     */
    public static bool load_file_to_textview(string path, AcmeDrawingTextView text_view, out string error_message) {
        error_message = "";
        
        try {
            var file = File.new_for_path(path);
            if (!file.query_exists()) {
                error_message = "File does not exist: " + path;
                return false;
            }
            
            uint8[] contents;
            string etag_out;
            file.load_contents(null, out contents, out etag_out);
            
            string text = (string) contents;
            text_view.set_text(text);
            
            return true;
        } catch (Error e) {
            error_message = "Error loading file: " + e.message;
            return false;
        }
    }
    
    /**
     * Save text buffer content to a file
     */
    public static bool save_file(string path, Gtk.TextBuffer buffer, out string error_message) {
        error_message = "";
        
        try {
            Gtk.TextIter start, end;
            buffer.get_start_iter(out start);
            buffer.get_end_iter(out end);
            string text = buffer.get_text(start, end, true);
            
            var file = File.new_for_path(path);
            
            var parent = file.get_parent();
            if (parent != null && !parent.query_exists()) {
                try {
                    parent.make_directory_with_parents();
                } catch (Error e) {
                    error_message = "Error creating directory: " + e.message;
                    return false;
                }
            }
            
            FileOutputStream stream;
            if (file.query_exists()) {
                stream = file.replace(null, false, FileCreateFlags.NONE);
            } else {
                stream = file.create(FileCreateFlags.NONE);
            }
            
            stream.write(text.data);
            
            return true;
        } catch (Error e) {
            error_message = "Error saving file: " + e.message;
            return false;
        }
    }
    
    /**
     * Save text content from an AcmeDrawingTextView to a file
     */
    public static bool save_file_from_textview(string path, AcmeDrawingTextView text_view, out string error_message) {
        error_message = "";
        
        try {
            string text = text_view.get_text();
            
            var file = File.new_for_path(path);
            
            var parent = file.get_parent();
            if (parent != null && !parent.query_exists()) {
                try {
                    parent.make_directory_with_parents();
                } catch (Error e) {
                    error_message = "Error creating directory: " + e.message;
                    return false;
                }
            }
            
            FileOutputStream stream;
            if (file.query_exists()) {
                stream = file.replace(null, false, FileCreateFlags.NONE);
            } else {
                stream = file.create(FileCreateFlags.NONE);
            }
            
            stream.write(text.data);
            
            return true;
        } catch (Error e) {
            error_message = "Error saving file: " + e.message;
            return false;
        }
    }
    
    /**
     * Get directory listing - SIMPLIFIED approach, readable and maintainable
     */
    public static string get_directory_listing(string path, Pango.FontDescription? font_desc = null, int target_width = 800) {
        try {
            var dir = File.new_for_path(path);
            
            if (!dir.query_exists()) {
                return "Directory does not exist: " + path;
            }
            
            var file_info = dir.query_info("standard::*", FileQueryInfoFlags.NONE);
            if (file_info.get_file_type() != FileType.DIRECTORY) {
                return path + " is not a directory";
            }
            
            var entries = collect_directory_entries(dir);
            
            // Simple decision: either single column or basic multi-column
            if (font_desc != null && target_width > 400 && entries.length > 10) {
                return format_multi_column(entries, target_width);
            } else {
                return format_single_column(entries);
            }
            
        } catch (Error e) {
            return "Error listing directory: " + e.message;
        }
    }
    
    // Collect and sort directory entries in Acme order
    private static string[] collect_directory_entries(File dir) throws Error {
        var dot_dirs = new Array<string>();
        var dot_files = new Array<string>();
        var reg_dirs = new Array<string>();
        var reg_files = new Array<string>();
        
        var enumerator = dir.enumerate_children(
            "standard::*,unix::mode,access::can-execute",
            FileQueryInfoFlags.NONE
        );
        
        FileInfo info;
        while ((info = enumerator.next_file()) != null) {
            string name = info.get_name();
            string display_name = format_entry_name(info);
            
            // Sort into categories: dot dirs, dot files, regular dirs, regular files
            if (name.has_prefix(".")) {
                if (info.get_file_type() == FileType.DIRECTORY) {
                    dot_dirs.append_val(display_name);
                } else {
                    dot_files.append_val(display_name);
                }
            } else {
                if (info.get_file_type() == FileType.DIRECTORY) {
                    reg_dirs.append_val(display_name);
                } else {
                    reg_files.append_val(display_name);
                }
            }
        }
        
        // Combine in Acme order and sort each category
        var result = new Array<string>();
        append_sorted_array(result, dot_dirs);
        append_sorted_array(result, dot_files);
        append_sorted_array(result, reg_dirs);
        append_sorted_array(result, reg_files);
        
        // Convert to string array
        string[] entries = new string[result.length];
        for (int i = 0; i < result.length; i++) {
            entries[i] = result.index(i);
        }
        
        return entries;
    }
    
    // Format entry name based on type (directory/, executable*)
    private static string format_entry_name(FileInfo info) {
        string name = info.get_name();
        
        if (info.get_file_type() == FileType.DIRECTORY) {
            return name + "/";
        }
        
        // Check if executable
        bool is_executable = false;
        if (info.has_attribute("access::can-execute")) {
            is_executable = info.get_attribute_boolean("access::can-execute");
        } else if (info.has_attribute("unix::mode")) {
            uint32 mode = info.get_attribute_uint32("unix::mode");
            is_executable = (mode & 0111) != 0;
        }
        
        return is_executable ? name + "*" : name;
    }
    
    // Simple alphabetical sort within category
    private static void append_sorted_array(Array<string> target, Array<string> source) {
        // Convert to regular array for sorting
        string[] temp = new string[source.length];
        for (int i = 0; i < source.length; i++) {
            temp[i] = source.index(i);
        }
        
        // Simple insertion sort - fine for directory listings
        for (int i = 1; i < temp.length; i++) {
            string key = temp[i];
            int j = i - 1;
            while (j >= 0 && temp[j] > key) {
                temp[j + 1] = temp[j];
                j--;
            }
            temp[j + 1] = key;
        }
        
        // Add to target
        for (int i = 0; i < temp.length; i++) {
            target.append_val(temp[i]);
        }
    }
    
    // Simple single column format
    private static string format_single_column(string[] entries) {
        var sb = new StringBuilder();
        for (int i = 0; i < entries.length; i++) {
            sb.append(entries[i]);
            sb.append("\n");
        }
        return sb.str;
    }
    
    // Simple multi-column format with basic heuristics
    private static string format_multi_column(string[] entries, int target_width) {
        if (entries.length == 0) return "";
        
        // Simple heuristic for column count based on entry count and width
        int columns = 1;
        if (entries.length > 30 && target_width > 600) {
            columns = 4;
        } else if (entries.length > 15 && target_width > 450) {
            columns = 3;
        } else if (entries.length > 8 && target_width > 300) {
            columns = 2;
        }
        
        if (columns == 1) {
            return format_single_column(entries);
        }
        
        // Calculate rows needed
        int rows = (entries.length + columns - 1) / columns;
        
        var sb = new StringBuilder();
        
        // Format row by row
        for (int row = 0; row < rows; row++) {
            for (int col = 0; col < columns; col++) {
                int index = row * columns + col;
                if (index >= entries.length) break;
                
                sb.append(entries[index]);
                
                // Add spacing between columns (simple approach)
                if (col < columns - 1 && index + 1 < entries.length) {
                    // Calculate spacing based on current entry length
                    int current_len = entries[index].length;
                    int spaces_needed = (int)Math.fmax(2, 20 - current_len);
                    for (int s = 0; s < spaces_needed; s++) {
                        sb.append(" ");
                    }
                }
            }
            sb.append("\n");
        }
        
        return sb.str;
    }
}