/* command_manager.vala
 * Unified command system
 */

/* Command class represents a single command in the ACME editor */
public class AcmeCommand : Object {
    public string name { get; private set; }
    public CommandScope scope { get; private set; }
    
    public delegate void CommandCallback(AcmeCommandContext context);
    private CommandCallback callback;
    
    public AcmeCommand(string name, CommandScope scope, owned CommandCallback callback) {
        this.name = name;
        this.scope = scope;
        this.callback = (owned) callback;
    }
    
    public void execute(AcmeCommandContext context) {
        callback(context);
    }
}

/* Scope of command execution */
public enum CommandScope {
    GLOBAL,    // Main tag commands (NewCol, PutAll, etc.)
    COLUMN,    // Column tag commands (New, Cut, etc.)
    WINDOW     // Window-specific commands (Get, Put, etc.)
}

/* Context for command execution, provides access to relevant objects */
public class AcmeCommandContext : Object {
    public weak AcmeWindow? window { get; set; default = null; }
    public weak AcmeColumn? column { get; set; default = null; }
    public weak AcmeTextView? text_view { get; set; default = null; }
    public string command_text { get; set; default = ""; }
    
    public AcmeCommandContext() {
    }
    
    public AcmeCommandContext.with_window(AcmeWindow window) {
        this.window = window;
    }
    
    public AcmeCommandContext.with_column(AcmeColumn column) {
        this.column = column;
        this.window = column.get_root() as AcmeWindow;
    }
    
    public AcmeCommandContext.with_text_view(AcmeTextView text_view) {
        this.text_view = text_view;
        
        // Find parent column
        Gtk.Widget? parent = text_view.get_parent();
        while (parent != null && !(parent is AcmeColumn)) {
            parent = parent.get_parent();
        }
        
        if (parent != null) {
            this.column = (AcmeColumn) parent;
        }
        
        // Find window
        this.window = text_view.get_root() as AcmeWindow;
    }
}

/* File watcher for Watch command */
public class AcmeFileWatcher : Object {
    public string command { get; private set; }
    public string directory { get; private set; }
    public AcmeTextView? target_view { get; private set; }
    
    private FileMonitor monitor;
    private uint timeout_id = 0;
    
    public AcmeFileWatcher(string command, string directory, AcmeTextView? target_view = null) {
        this.command = command;
        this.directory = directory;
        this.target_view = target_view;
        start_watching();
    }
    
    private void start_watching() {
        try {
            var file = File.new_for_path(directory);
            monitor = file.monitor_directory(FileMonitorFlags.NONE, null);
            
            monitor.changed.connect((file, other_file, event_type) => {
                if (event_type == FileMonitorEvent.CHANGES_DONE_HINT) {
                    // Debounce the command execution - wait 500ms after last change
                    if (timeout_id > 0) {
                        Source.remove(timeout_id);
                    }
                    
                    timeout_id = Timeout.add(500, () => {
                        execute_watched_command();
                        timeout_id = 0;
                        return false; // Don't repeat
                    });
                }
            });
            
            print("Watching directory: %s for command: %s\n", directory, command);
        } catch (Error e) {
            warning("Failed to watch directory %s: %s", directory, e.message);
        }
    }
    
    private void execute_watched_command() {
        print("File change detected, executing: %s\n", command);
        
        if (target_view != null && target_view.get_root() != null) {
            // Execute the command through the text view
            target_view.execute_command_internal(command);
        }
    }
    
    public void stop_watching() {
        if (monitor != null) {
            monitor.cancel();
        }
        
        if (timeout_id > 0) {
            Source.remove(timeout_id);
            timeout_id = 0;
        }
    }
}

/* Central manager for all ACME commands */
public class AcmeCommandManager : Object {
    private static AcmeCommandManager? instance;
    private HashTable<string, AcmeCommand> commands;
    private List<AcmeFileWatcher> watchers;
    
    private AcmeCommandManager() {
        commands = new HashTable<string, AcmeCommand>(str_hash, str_equal);
        watchers = new List<AcmeFileWatcher>();
        register_standard_commands();
    }
    
    public static AcmeCommandManager get_instance() {
        if (instance == null) {
            instance = new AcmeCommandManager();
        }
        return instance;
    }
    
    public void register_command(AcmeCommand command) {
        commands.insert(command.name, command);
    }
    
    public bool execute_command(string name, AcmeCommandContext context) {
        var command = commands.lookup(name);
        if (command != null) {
            command.execute(context);
            return true;
        }
        
        // Check for prefixed commands like "Get" or "Put"
        foreach (string cmd_name in commands.get_keys()) {
            if (name.has_prefix(cmd_name + " ")) {
                command = commands.lookup(cmd_name);
                if (command != null) {
                    // Add the full command text to the context
                    context.command_text = name;
                    command.execute(context);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    // Check if a command exists
    public bool is_valid_command(string command) {
        return commands.contains(command);
    }
    
    // Stop all watchers (called on shutdown)
    public void stop_all_watchers() {
        foreach (var watcher in watchers) {
            watcher.stop_watching();
        }
        watchers = null;
    }
    
    private void register_standard_commands() {
        // Main window commands
        register_command(new AcmeCommand("Newcol", CommandScope.GLOBAL, (context) => {
            if (context.window != null)
                context.window.on_newcol_clicked();
        }));
        
        register_command(new AcmeCommand("Putall", CommandScope.GLOBAL, (context) => {
            if (context.window != null)
                context.window.on_putall_clicked();
        }));
        
        register_command(new AcmeCommand("Kill", CommandScope.GLOBAL, (context) => {
            if (context.window != null)
                context.window.on_kill_clicked();
        }));
        
        register_command(new AcmeCommand("Dump", CommandScope.GLOBAL, (context) => {
            if (context.window != null)
                context.window.on_dump_clicked();
        }));
        
        register_command(new AcmeCommand("Load", CommandScope.GLOBAL, (context) => {
            if (context.window != null)
                context.window.on_load_clicked();
        }));
        
        register_command(new AcmeCommand("Exit", CommandScope.GLOBAL, (context) => {
            if (context.window != null)
                context.window.on_exit_clicked();
        }));
        
        // Column commands
        register_command(new AcmeCommand("New", CommandScope.COLUMN, (context) => {
            if (context.column != null)
                context.column.on_new_clicked();
        }));
        
        register_command(new AcmeCommand("Cut", CommandScope.COLUMN, (context) => {
            if (context.column != null)
                context.column.on_cut_clicked();
        }));
        
        register_command(new AcmeCommand("Paste", CommandScope.COLUMN, (context) => {
            if (context.column != null)
                context.column.on_paste_clicked();
        }));
        
        register_command(new AcmeCommand("Snarf", CommandScope.COLUMN, (context) => {
            if (context.column != null)
                context.column.on_snarf_clicked();
        }));
        
        register_command(new AcmeCommand("Sort", CommandScope.COLUMN, (context) => {
            if (context.column != null)
                context.column.on_sort_clicked();
        }));
        
        register_command(new AcmeCommand("Zerox", CommandScope.COLUMN, (context) => {
            if (context.column != null)
                context.column.on_zerox_clicked();
        }));
        
        register_command(new AcmeCommand("Delcol", CommandScope.COLUMN, (context) => {
            if (context.column != null)
                context.column.on_delcol_clicked();
        }));
        
        // Window commands
        register_command(new AcmeCommand("Del", CommandScope.WINDOW, (context) => {
            if (context.text_view != null)
                context.text_view.close_requested();
        }));
        
        register_command(new AcmeCommand("Get", CommandScope.WINDOW, (context) => {
            if (context.text_view != null) {
                string path = "";
                if (context.command_text != "" && context.command_text.has_prefix("Get ")) {
                    path = context.command_text.substring(4).strip();
                } else {
                    path = context.text_view.get_filename();
                }
                context.text_view.execute_get(path);
            }
        }));
        
        register_command(new AcmeCommand("Put", CommandScope.WINDOW, (context) => {
            if (context.text_view != null) {
                string path = "";
                if (context.command_text != "" && context.command_text.has_prefix("Put ")) {
                    path = context.command_text.substring(4).strip();
                }
                context.text_view.execute_put(path);
            }
        }));
        
        register_command(new AcmeCommand("Split", CommandScope.WINDOW, (context) => {
            if (context.text_view != null)
                context.text_view.split_requested();
        }));
        
        register_command(new AcmeCommand("Undo", CommandScope.WINDOW, (context) => {
            if (context.text_view != null)
                context.text_view.execute_undo();
        }));
        
        register_command(new AcmeCommand("Redo", CommandScope.WINDOW, (context) => {
            if (context.text_view != null)
                context.text_view.execute_redo();
        }));
        
        // Additional commands
        register_command(new AcmeCommand("Ls", CommandScope.WINDOW, (context) => {
            if (context.text_view != null)
                context.text_view.execute_ls();
        }));
        
        register_command(new AcmeCommand("Col", CommandScope.WINDOW, (context) => {
            if (context.text_view != null && context.command_text.has_prefix("Col ")) {
                string col_num_str = context.command_text.substring(4).strip();
                int col_num = int.parse(col_num_str);
                context.text_view.move_to_column_requested(col_num - 1); // 0-based index
            }
        }));
        
        register_command(new AcmeCommand("Look", CommandScope.WINDOW, (context) => {
            if (context.text_view != null) {
                string pattern = "";
                if (context.command_text != "" && context.command_text.has_prefix("Look ")) {
                    pattern = context.command_text.substring(5).strip();
                    AcmeSearch.get_instance().execute_look(pattern, context.text_view);
                }
            }
        }));
        
        register_command(new AcmeCommand("Edit", CommandScope.WINDOW, (context) => {
            if (context.text_view != null && context.command_text.has_prefix("Edit ")) {
                string edit_command = context.command_text.substring(5).strip();
                AcmeEditCommand.get_instance().execute(edit_command, context.text_view);
            }
        }));
        
        register_command(new AcmeCommand("Font", CommandScope.GLOBAL, (context) => {
            if (context.window != null && context.command_text.has_prefix("Font ")) {
                string font_spec = context.command_text.substring(5).strip();
                context.window.update_all_fonts(font_spec);
            }
        }));
        
        // Watch command
        register_command(new AcmeCommand("Watch", CommandScope.WINDOW, (context) => {
            if (context.text_view != null && context.command_text.has_prefix("Watch ")) {
                string watch_command = context.command_text.substring(6).strip();
                start_watch(watch_command, context.text_view);
            }
        }));
        
        register_command(new AcmeCommand("Win", CommandScope.COLUMN, (context) => {
            if (context.column != null) {
                string shell_cmd = "zsh";  // Default shell
                
                // Parse command to get shell or command to run
                if (context.command_text.has_prefix("Win ")) {
                    string args = context.command_text.substring(4).strip();
                    if (args != "") {
                        shell_cmd = args;
                    }
                }
                
                // Create new text view for the terminal
                var text_view = new AcmeTextView();
                text_view.update_filename("+" + shell_cmd);
                context.column.add_text_view(text_view);
                
                // Start the terminal session
                start_terminal_session(text_view, shell_cmd);
            }
        }));
    }
    
    // Terminal session management class
    private class TerminalSession : Object {
        public AcmeTextView text_view;
        public Subprocess process;
        public OutputStream stdin_stream;
        public InputStream stdout_stream;
        
        private DataInputStream stdout_reader;
        public int prompt_line = 0;
        public int prompt_col = 0;
        public bool waiting_for_input = true;
        public StringBuilder pending_output;
        
        public TerminalSession(AcmeTextView tv, Subprocess proc, OutputStream stdin, InputStream stdout) {
            text_view = tv;
            process = proc;
            stdin_stream = stdin;
            stdout_stream = stdout;
            pending_output = new StringBuilder();
            
            stdout_reader = new DataInputStream(stdout_stream);
            
            // Start reading output
            read_output.begin();
        }
        
        private async void read_output() {
            try {
                var buffer = new uint8[1];
                while (true) {
                    var bytes_read = yield stdout_reader.read_async(buffer);
                    if (bytes_read == 0) break;
                    
                    char c = (char)buffer[0];
                    
                    // Handle different characters
                    if (c == '\n') {
                        // Newline - flush pending output and add newline
                        if (pending_output.len > 0) {
                            text_view.text_view.insert_text(pending_output.str);
                            pending_output = new StringBuilder();
                        }
                        text_view.text_view.insert_text("\n");
                        
                        // After command output, show new prompt
                        if (!waiting_for_input) {
                            text_view.text_view.insert_text("% ");
                            update_prompt_position();
                            waiting_for_input = true;
                        }
                    } else if (c == '\r') {
                        // Carriage return - ignore
                        continue;
                    } else if (c == '%' && waiting_for_input && pending_output.len == 0) {
                        // This might be a prompt character, but we already handle prompts
                        // Skip it to avoid duplication
                        continue;
                    } else {
                        // Regular character
                        pending_output.append_c(c);
                    }
                    
                    text_view.scroll_to_end();
                }
            } catch (Error e) {
                text_view.text_view.insert_text("\n[Terminal session ended]\n");
            }
        }
        
        public void send_command(string cmd) {
            try {
                // Send the command
                stdin_stream.write(cmd.data);
                stdin_stream.flush();
                
                // Add the command to our view (echo it)
                text_view.text_view.insert_text(cmd);
                
                waiting_for_input = false;
            } catch (Error e) {
                text_view.text_view.insert_text("Error sending command: " + e.message + "\n");
            }
        }
        
        public void update_prompt_position() {
            // Store current cursor position as prompt position
            prompt_line = text_view.text_view.cursor_line;
            prompt_col = text_view.text_view.cursor_col;
        }
        
        public bool is_after_prompt() {
            return text_view.text_view.cursor_line > prompt_line || 
                   (text_view.text_view.cursor_line == prompt_line && 
                    text_view.text_view.cursor_col >= prompt_col);
        }
    }
    
    private void start_terminal_session(AcmeTextView text_view, string command) {
        try {
            // Create subprocess with pty for proper terminal behavior
            SubprocessLauncher launcher = new SubprocessLauncher(
                SubprocessFlags.STDIN_PIPE | 
                SubprocessFlags.STDOUT_PIPE | 
                SubprocessFlags.STDERR_MERGE
            );
            
            // Set up environment for interactive shell
            string[] env = Environ.get();
            launcher.set_environ(env);
            
            // Start the process in interactive mode
            Subprocess process = launcher.spawn(command, "-i");
            
            // Get the streams
            var stdin = process.get_stdin_pipe();
            var stdout = process.get_stdout_pipe();
            
            // Create a terminal session object to manage state
            var terminal_session = new TerminalSession(text_view, process, stdin, stdout);
            
            // Store session in text view data
            text_view.set_data("terminal_session", terminal_session);
            
            // Set up terminal-specific tag line
            text_view.set_tag_content(command + " Del Snarf | ");
            
            // Make the text view behave like a terminal
            setup_terminal_behavior(text_view, terminal_session);
            
            // Start with a prompt
            text_view.text_view.insert_text("% ");
            terminal_session.update_prompt_position();
            
        } catch (Error e) {
            text_view.text_view.insert_text("Error starting terminal: " + e.message + "\n");
        }
    }

    private void setup_terminal_behavior(AcmeTextView text_view, TerminalSession session) {
        // Override key handling for terminal behavior
        var key_controller = new Gtk.EventControllerKey();
        key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        text_view.text_view.add_controller(key_controller);
        
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            // Handle Enter key
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                if (session.waiting_for_input && session.is_after_prompt()) {
                    // Get the command line (from prompt to cursor)
                    string command = get_current_command_line(text_view, session);
                    session.send_command(command + "\n");
                    return true;  // Consume the event
                }
            }
            
            // Handle Backspace - don't allow deletion before prompt
            if (keyval == Gdk.Key.BackSpace) {
                if (!session.is_after_prompt()) {
                    return true;  // Consume the event (prevent deletion)
                }
            }
            
            // Handle Up/Down arrows for command history (simplified)
            if (keyval == Gdk.Key.Up || keyval == Gdk.Key.Down) {
                // In a full implementation, you'd implement command history here
                return true;
            }
            
            return false;  // Let other keys through
        });
        
        // Prevent editing before the prompt
        text_view.text_view.cursor_moved.connect(() => {
            if (!session.is_after_prompt()) {
                // Move cursor back to after prompt
                text_view.text_view.cursor_line = session.prompt_line;
                text_view.text_view.cursor_col = session.prompt_col;
                text_view.text_view.queue_draw();
            }
        });
        
        // Handle Ctrl+C
        var ctrl_handler = new Gtk.EventControllerKey();
        text_view.text_view.add_controller(ctrl_handler);
        
        ctrl_handler.key_pressed.connect((keyval, keycode, state) => {
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && keyval == Gdk.Key.c) {
                // Send SIGINT to the process
                session.process.send_signal(Posix.Signal.INT);
                return true;
            }
            return false;
        });
    }

    private string get_current_command_line(AcmeTextView text_view, TerminalSession session) {
        // Get text from prompt position to cursor
        if (text_view.text_view.cursor_line == session.prompt_line) {
            // Single line command
            string line = text_view.text_view.lines[session.prompt_line];
            return line.substring(session.prompt_col, 
                                 text_view.text_view.cursor_col - session.prompt_col);
        } else {
            // Multi-line command (shouldn't happen often in shell)
            // For simplicity, just get the current line
            return text_view.text_view.lines[text_view.text_view.cursor_line];
        }
    }
    
    private void start_watch(string command, AcmeTextView text_view) {
        // Get the directory to watch (current file's directory or current working directory)
        string watch_dir;
        string filename = text_view.get_filename();
        
        if (filename != "Untitled" && filename != "+Errors") {
            // Watch the directory containing the current file
            watch_dir = Path.get_dirname(filename);
        } else {
            // Fall back to current working directory
            watch_dir = Environment.get_current_dir();
        }
        
        // Stop any existing watcher for this text view
        foreach (var watcher in watchers) {
            if (watcher.target_view == text_view) {
                watcher.stop_watching();
                watchers.remove(watcher);
                break;
            }
        }
        
        // Create and start new watcher
        var watcher = new AcmeFileWatcher(command, watch_dir, text_view);
        watchers.append(watcher);
        
        // Display confirmation message
        text_view.text_view.insert_text("Started watching " + watch_dir + " for changes\n");
        text_view.text_view.insert_text("Will execute: " + command + "\n\n");
    }
}