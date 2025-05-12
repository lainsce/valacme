/* filehandler.vala
 * File operations for ACME Vala with proportional font support
 */

public class AcmeFileHandler : Object {
    
    // Helper class for directory entries
    private class DirectoryEntry {
        public string name;
        public bool is_directory;
        public bool is_dot_file;
        public int width; // Cached width
    }
    
    /**
     * Load file content into a text buffer
     * @param path The file path to load
     * @param buffer The text buffer to load content into
     * @param error_message Output parameter for error message
     * @return True if successful, false otherwise
     */
    public static bool load_file(string path, Gtk.TextBuffer buffer, out string error_message) {
        error_message = "";
        
        try {
            // Check if the file exists
            var file = File.new_for_path(path);
            if (!file.query_exists()) {
                error_message = "File does not exist: " + path;
                return false;
            }
            
            // Read the file content
            uint8[] contents;
            string etag_out;
            file.load_contents(null, out contents, out etag_out);
            
            // Convert bytes to string
            string text = (string) contents;
            
            // Set the text buffer content
            buffer.set_text(text, text.length);
            
            return true;
        } catch (Error e) {
            error_message = "Error loading file: " + e.message;
            return false;
        }
    }
    
    /**
     * Load file content into an AcmeDrawingTextView
     * @param path The file path to load
     * @param text_view The AcmeDrawingTextView to load content into
     * @param error_message Output parameter for error message
     * @return True if successful, false otherwise
     */
    public static bool load_file_to_textview(string path, AcmeDrawingTextView text_view, out string error_message) {
        error_message = "";
        
        try {
            // Check if the file exists
            var file = File.new_for_path(path);
            if (!file.query_exists()) {
                error_message = "File does not exist: " + path;
                return false;
            }
            
            // Read the file content
            uint8[] contents;
            string etag_out;
            file.load_contents(null, out contents, out etag_out);
            
            // Convert bytes to string
            string text = (string) contents;
            
            // Set the text view content
            text_view.set_text(text);
            
            return true;
        } catch (Error e) {
            error_message = "Error loading file: " + e.message;
            return false;
        }
    }
    
    /**
     * Save text buffer content to a file
     * @param path The file path to save to
     * @param buffer The text buffer to save
     * @param error_message Output parameter for error message
     * @return True if successful, false otherwise
     */
    public static bool save_file(string path, Gtk.TextBuffer buffer, out string error_message) {
        error_message = "";
        
        try {
            // Get the text buffer content
            Gtk.TextIter start, end;
            buffer.get_start_iter(out start);
            buffer.get_end_iter(out end);
            string text = buffer.get_text(start, end, true);
            
            // Create or overwrite the file
            var file = File.new_for_path(path);
            
            // Create parent directories if they don't exist
            var parent = file.get_parent();
            if (parent != null && !parent.query_exists()) {
                try {
                    parent.make_directory_with_parents();
                } catch (Error e) {
                    error_message = "Error creating directory: " + e.message;
                    return false;
                }
            }
            
            // Write to the file
            FileOutputStream stream;
            if (file.query_exists()) {
                // Replace existing file
                stream = file.replace(null, false, FileCreateFlags.NONE);
            } else {
                // Create new file
                stream = file.create(FileCreateFlags.NONE);
            }
            
            // Write the text to the file
            stream.write(text.data);
            
            return true;
        } catch (Error e) {
            error_message = "Error saving file: " + e.message;
            return false;
        }
    }
    
    /**
     * Save text content from an AcmeDrawingTextView to a file
     * @param path The file path to save to
     * @param text_view The AcmeDrawingTextView containing the text to save
     * @param error_message Output parameter for error message
     * @return True if successful, false otherwise
     */
    public static bool save_file_from_textview(string path, AcmeDrawingTextView text_view, out string error_message) {
        error_message = "";
        
        try {
            // Get the text content
            string text = text_view.get_text();
            
            // Create or overwrite the file
            var file = File.new_for_path(path);
            
            // Create parent directories if they don't exist
            var parent = file.get_parent();
            if (parent != null && !parent.query_exists()) {
                try {
                    parent.make_directory_with_parents();
                } catch (Error e) {
                    error_message = "Error creating directory: " + e.message;
                    return false;
                }
            }
            
            // Write to the file
            FileOutputStream stream;
            if (file.query_exists()) {
                // Replace existing file
                stream = file.replace(null, false, FileCreateFlags.NONE);
            } else {
                // Create new file
                stream = file.create(FileCreateFlags.NONE);
            }
            
            // Write the text to the file
            stream.write(text.data);
            
            return true;
        } catch (Error e) {
            error_message = "Error saving file: " + e.message;
            return false;
        }
    }
    
    /**
     * Get the directory listing formatted for display
     * @param path The directory path to list
     * @param font_desc Optional font description for proportional formatting
     * @param target_width Optional target width for column layout
     * @return A string with the directory contents formatted appropriately
     */
    public static string get_directory_listing(string path, Pango.FontDescription? font_desc = null, int target_width = 800) {
        try {
            StringBuilder sb = new StringBuilder();
            
            // Create the directory object
            var dir = File.new_for_path(path);
            
            // Check if it's actually a directory
            if (!dir.query_exists()) {
                return "Directory does not exist: " + path;
            }
            
            var file_info = dir.query_info("standard::*", FileQueryInfoFlags.NONE);
            if (file_info.get_file_type() != FileType.DIRECTORY) {
                return path + " is not a directory";
            }
            
            // Get directory enumerator
            var enumerator = dir.enumerate_children(
                "standard::*,unix::mode,access::can-execute",
                FileQueryInfoFlags.NONE
            );
            
            // Arrays to store files and directories
            var all_entries = new Array<DirectoryEntry>();
            
            // Collect all entries
            FileInfo info;
            while ((info = enumerator.next_file()) != null) {
                string name = info.get_name();
                
                // Format name based on type
                string display_name;
                bool is_dir = false;
                
                if (info.get_file_type() == FileType.DIRECTORY) {
                    display_name = name + "/";
                    is_dir = true;
                } else {
                    // Check if file is executable
                    bool is_executable = false;
                    
                    if (info.has_attribute("access::can-execute")) {
                        is_executable = info.get_attribute_boolean("access::can-execute");
                    } else if (info.has_attribute("unix::mode")) {
                        uint32 mode = info.get_attribute_uint32("unix::mode");
                        is_executable = (mode & 0111) != 0;
                    }
                    
                    if (is_executable) {
                        display_name = name + "*";
                    } else {
                        display_name = name;
                    }
                }
                
                var entry = new DirectoryEntry();
                entry.name = display_name;
                entry.is_directory = is_dir;
                entry.is_dot_file = name.has_prefix(".");
                
                all_entries.append_val(entry);
            }
            
            // Sort entries: dot dirs, dot files, regular dirs, regular files
            all_entries.sort((a, b) => {
                // First by type (dot vs regular)
                if (a.is_dot_file != b.is_dot_file) {
                    return a.is_dot_file ? -1 : 1;
                }
                
                // Then by file type (directories first within each category)
                if (a.is_directory != b.is_directory) {
                    return a.is_directory ? -1 : 1;
                }
                
                return 0;
            });
            
            // Choose formatting based on available font information
            if (font_desc != null) {
                format_proportional_columns(all_entries, sb, font_desc, target_width);
            } else {
                // Fallback to simple single column for monospace or unknown fonts
                for (int i = 0; i < all_entries.length; i++) {
                    sb.append(all_entries.index(i).name);
                    sb.append("\n");
                }
            }
            
            return sb.str;
        } catch (Error e) {
            string error_msg = "Error listing directory: " + e.message;
            print("ERROR: %s\n", error_msg);
            return error_msg;
        }
    }
    
    // Format entries in proportional columns
    private static void format_proportional_columns(Array<DirectoryEntry> entries, StringBuilder sb, Pango.FontDescription font_desc, int target_width) {
        if (entries.length == 0) return;
        
        // Create a temporary Cairo context for measurement
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 1, 1);
        var cr = new Cairo.Context(surface);
        var layout = Pango.cairo_create_layout(cr);
        layout.set_font_description(font_desc);
        
        // Calculate widths for all entries
        for (int i = 0; i < entries.length; i++) {
            var entry = entries.index(i);
            layout.set_text(entry.name, -1);
            int width;
            layout.get_pixel_size(out width, null);
            entry.width = width;
        }
        
        surface.finish();
        
        // Find optimal column count
        int columns = determine_column_count(entries, target_width);
        
        if (columns <= 1) {
            // Single column fallback
            for (int i = 0; i < entries.length; i++) {
                sb.append(entries.index(i).name);
                sb.append("\n");
            }
            return;
        }
        
        // Calculate column widths
        var column_widths = calculate_column_widths(entries, columns);
        
        // Format in columns
        format_columns(entries, sb, columns, column_widths);
    }
    
    // Determine optimal number of columns
    private static int determine_column_count(Array<DirectoryEntry> entries, int target_width) {
        if (entries.length == 0) return 1;
        
        // Find the widest entry
        int max_width = 0;
        for (int i = 0; i < entries.length; i++) {
            if (entries.index(i).width > max_width) {
                max_width = entries.index(i).width;
            }
        }
        
        // Minimum space between columns
        int column_spacing = 56;
        
        // Add some debug output
        print("Target width: %d, Max entry width: %d\n", target_width, max_width);
        
        // Try different column counts (starting from most columns)
        for (int cols = 5; cols >= 2; cols--) {
            int total_width = 0;
            
            // Calculate width needed for this column count
            for (int col = 0; col < cols; col++) {
                int col_width = 0;
                
                // Find widest entry in this column
                for (int i = col; i < entries.length; i += cols) {
                    if (entries.index(i).width > col_width) {
                        col_width = entries.index(i).width;
                    }
                }
                
                total_width += col_width;
                if (col < cols - 1) total_width += column_spacing;
            }
            
            print("Trying %d columns, total width needed: %d\n", cols, total_width);
            
            // If this fits (with some margin), use this column count
            if (total_width <= target_width - 20) { // Leave 20px margin
                print("Using %d columns\n", cols);
                return cols;
            }
        }
        
        print("Falling back to 1 column\n");
        return 1; // Fallback to single column
    }
    
    // Calculate width for each column
    private static int[] calculate_column_widths(Array<DirectoryEntry> entries, int columns) {
        var widths = new int[columns];
        
        for (int col = 0; col < columns; col++) {
            widths[col] = 0;
            
            // Find widest entry in this column
            for (int i = col; i < entries.length; i += columns) {
                if (entries.index(i).width > widths[col]) {
                    widths[col] = entries.index(i).width;
                }
            }
        }
        
        return widths;
    }
    
    // Format entries into columns with proper alignment
    private static void format_columns(Array<DirectoryEntry> entries, StringBuilder sb, int columns, int[] column_widths) {
        int rows = ((int)entries.length + columns) / columns; // Ceiling division
        
        for (int row = 0; row < rows; row++) {
            for (int col = 0; col < columns; col++) {
                int index = row * columns + col;
                
                if (index >= entries.length) break;
                
                var entry = entries.index(index);
                sb.append(entry.name);
                
                // Add padding if not the last column AND if there's another entry to the right in this row
                if (col < columns - 1 && index + 1 < entries.length) {
                    // Calculate total space needed: align to column boundary + 56 pixels of spacing
                    int current_width = entry.width;
                    int column_end = column_widths[col];
                    int target_spacing_pixels = 56;
                    
                    // Total pixels needed from current position to next column
                    int total_pixels_needed = (column_end - current_width) + target_spacing_pixels;
                    
                    // Convert pixels to spaces using actual space width
                    int spaces_to_add = (int)Math.round((double)total_pixels_needed / 4);
                    
                    // Ensure minimum reasonable spacing (at least 2 spaces)
                    spaces_to_add = (int)Math.fmax(spaces_to_add, 2);
                    
                    for (int p = 0; p < spaces_to_add; p++) {
                        sb.append(" ");
                    }
                }
            }
            sb.append("\n");
        }
    }
}