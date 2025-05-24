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
                    if (timeout_id > 0) {
                        Source.remove(timeout_id);
                    }
                    
                    timeout_id = Timeout.add(500, () => {
                        execute_watched_command();
                        timeout_id = 0;
                        return false;
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

/* Central manager for all ACME commands - Data-driven approach */
public class AcmeCommandManager : Object {
    private static AcmeCommandManager? instance;
    private HashTable<string, AcmeCommand> commands;
    private List<AcmeFileWatcher> watchers;
    
    // Command definition struct for data-driven registration
    private struct CommandDef {
        string name;
        CommandScope scope;
        string method_name;
    }
    
    // All commands in one place - easy to maintain and extend
    private static CommandDef[] STANDARD_COMMANDS = {
        // Global commands
        {"Newcol", CommandScope.GLOBAL, "newcol"},
        {"Putall", CommandScope.GLOBAL, "putall"},
        {"Kill", CommandScope.GLOBAL, "kill"},
        {"Dump", CommandScope.GLOBAL, "dump"},
        {"Load", CommandScope.GLOBAL, "load"},
        {"Exit", CommandScope.GLOBAL, "exit"},
        {"Font", CommandScope.GLOBAL, "font"},
        
        // Column commands
        {"New", CommandScope.COLUMN, "new"},
        {"Cut", CommandScope.COLUMN, "cut"},
        {"Paste", CommandScope.COLUMN, "paste"},
        {"Snarf", CommandScope.COLUMN, "snarf"},
        {"Sort", CommandScope.COLUMN, "sort"},
        {"Zerox", CommandScope.COLUMN, "zerox"},
        {"Delcol", CommandScope.COLUMN, "delcol"},
        {"Win", CommandScope.COLUMN, "win"},
        
        // Window commands
        {"Del", CommandScope.WINDOW, "del"},
        {"Get", CommandScope.WINDOW, "get"},
        {"Put", CommandScope.WINDOW, "put"},
        {"Split", CommandScope.WINDOW, "split"},
        {"Undo", CommandScope.WINDOW, "undo"},
        {"Redo", CommandScope.WINDOW, "redo"},
        {"Ls", CommandScope.WINDOW, "ls"},
        {"Col", CommandScope.WINDOW, "col"},
        {"Look", CommandScope.WINDOW, "look"},
        {"Edit", CommandScope.WINDOW, "edit"},
        {"Watch", CommandScope.WINDOW, "watch"}
    };
    
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
                    context.command_text = name;
                    command.execute(context);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    public bool is_valid_command(string command) {
        return commands.contains(command);
    }
    
    public void stop_all_watchers() {
        foreach (var watcher in watchers) {
            watcher.stop_watching();
        }
        watchers = null;
    }
    
    // Data-driven command registration - much cleaner
    private void register_standard_commands() {
        foreach (var def in STANDARD_COMMANDS) {
            register_command(new AcmeCommand(def.name, def.scope, (context) => {
                execute_standard_command(def.method_name, context);
            }));
        }
    }
    
    // Single dispatch method instead of dozens of individual registrations
    private void execute_standard_command(string method_name, AcmeCommandContext context) {
        switch (method_name) {
            // Global commands
            case "newcol": context.window?.on_newcol_clicked(); break;
            case "putall": context.window?.on_putall_clicked(); break;
            case "kill": context.window?.on_kill_clicked(); break;
            case "dump": context.window?.on_dump_clicked(); break;
            case "load": context.window?.on_load_clicked(); break;
            case "exit": context.window?.on_exit_clicked(); break;
            case "font": execute_font_command(context); break;
                
            // Column commands
            case "new": context.column?.on_new_clicked(); break;
            case "cut": context.column?.on_cut_clicked(); break;
            case "paste": context.column?.on_paste_clicked(); break;
            case "snarf": context.column?.on_snarf_clicked(); break;
            case "sort": context.column?.on_sort_clicked(); break;
            case "zerox": context.column?.on_zerox_clicked(); break;
            case "delcol": context.column?.on_delcol_clicked(); break;
            case "win": execute_win_command(context); break;
            
            // Window commands
            case "del": context.text_view?.close_requested(); break;
            case "get": execute_get_command(context); break;
            case "put": execute_put_command(context); break;
            case "split": context.text_view?.split_requested(); break;
            case "undo": context.text_view?.execute_undo(); break;
            case "redo": context.text_view?.execute_redo(); break;
            case "ls": context.text_view?.execute_ls(); break;
            case "col": execute_col_command(context); break;
            case "look": execute_look_command(context); break;
            case "edit": execute_edit_command(context); break;
            case "watch": execute_watch_command(context); break;
        }
    }
    
    // Helper methods for parameterized commands
    private void execute_font_command(AcmeCommandContext context) {
        if (context.command_text.has_prefix("Font ")) {
            string font_spec = context.command_text.substring(5).strip();
            context.window?.update_all_fonts(font_spec);
        }
    }
    
    private void execute_get_command(AcmeCommandContext context) {
        string path = "";
        if (context.command_text.has_prefix("Get ")) {
            path = context.command_text.substring(4).strip();
        } else {
            path = context.text_view?.get_filename() ?? "";
        }
        context.text_view?.execute_get(path);
    }
    
    private void execute_put_command(AcmeCommandContext context) {
        string path = "";
        if (context.command_text.has_prefix("Put ")) {
            path = context.command_text.substring(4).strip();
        }
        context.text_view?.execute_put(path);
    }
    
    private void execute_col_command(AcmeCommandContext context) {
        if (context.command_text.has_prefix("Col ")) {
            string col_num_str = context.command_text.substring(4).strip();
            int col_num = int.parse(col_num_str);
            context.text_view?.move_to_column_requested(col_num - 1);
        }
    }
    
    private void execute_look_command(AcmeCommandContext context) {
        if (context.command_text.has_prefix("Look ")) {
            string pattern = context.command_text.substring(5).strip();
            AcmeSearch.get_instance().execute_look(pattern, context.text_view);
        }
    }
    
    private void execute_edit_command(AcmeCommandContext context) {
        if (context.command_text.has_prefix("Edit ")) {
            string edit_command = context.command_text.substring(5).strip();
            AcmeEditCommand.get_instance().execute(edit_command, context.text_view);
        }
    }
    
    private void execute_watch_command(AcmeCommandContext context) {
        if (context.command_text.has_prefix("Watch ")) {
            string watch_command = context.command_text.substring(6).strip();
            start_watch(watch_command, context.text_view);
        }
    }
    
    private void execute_win_command(AcmeCommandContext context) {
        string shell_cmd = "zsh";
        if (context.command_text.has_prefix("Win ")) {
            string args = context.command_text.substring(4).strip();
            if (args != "") shell_cmd = args;
        }
        
        var text_view = new AcmeTextView();
        text_view.update_filename("+" + shell_cmd);
        context.column?.add_text_view(text_view);
        start_terminal_session(text_view, shell_cmd);
    }
    
    // Terminal session management - kept as in original for now
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
            read_output.begin();
        }
        
        private async void read_output() {
            try {
                var buffer = new uint8[1];
                while (true) {
                    var bytes_read = yield stdout_reader.read_async(buffer);
                    if (bytes_read == 0) break;
                    
                    char c = (char)buffer[0];
                    
                    if (c == '\n') {
                        if (pending_output.len > 0) {
                            text_view.text_view.insert_text(pending_output.str);
                            pending_output = new StringBuilder();
                        }
                        text_view.text_view.insert_text("\n");
                        
                        if (!waiting_for_input) {
                            text_view.text_view.insert_text("% ");
                            update_prompt_position();
                            waiting_for_input = true;
                        }
                    } else if (c == '\r') {
                        continue;
                    } else if (c == '%' && waiting_for_input && pending_output.len == 0) {
                        continue;
                    } else {
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
                stdin_stream.write(cmd.data);
                stdin_stream.flush();
                text_view.text_view.insert_text(cmd);
                waiting_for_input = false;
            } catch (Error e) {
                text_view.text_view.insert_text("Error sending command: " + e.message + "\n");
            }
        }
        
        public void update_prompt_position() {
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
            SubprocessLauncher launcher = new SubprocessLauncher(
                SubprocessFlags.STDIN_PIPE | 
                SubprocessFlags.STDOUT_PIPE | 
                SubprocessFlags.STDERR_MERGE
            );
            
            string[] env = Environ.get();
            launcher.set_environ(env);
            
            Subprocess process = launcher.spawn(command, "-i");
            var stdin = process.get_stdin_pipe();
            var stdout = process.get_stdout_pipe();
            
            var terminal_session = new TerminalSession(text_view, process, stdin, stdout);
            text_view.set_data("terminal_session", terminal_session);
            text_view.set_tag_content(command + " Del Snarf | ");
            
            setup_terminal_behavior(text_view, terminal_session);
            text_view.text_view.insert_text("% ");
            terminal_session.update_prompt_position();
            
        } catch (Error e) {
            text_view.text_view.insert_text("Error starting terminal: " + e.message + "\n");
        }
    }

    private void setup_terminal_behavior(AcmeTextView text_view, TerminalSession session) {
        var key_controller = new Gtk.EventControllerKey();
        key_controller.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        text_view.text_view.add_controller(key_controller);
        
        key_controller.key_pressed.connect((keyval, keycode, state) => {
            if (keyval == Gdk.Key.Return || keyval == Gdk.Key.KP_Enter) {
                if (session.waiting_for_input && session.is_after_prompt()) {
                    string command = get_current_command_line(text_view, session);
                    session.send_command(command + "\n");
                    return true;
                }
            }
            
            if (keyval == Gdk.Key.BackSpace) {
                if (!session.is_after_prompt()) {
                    return true;
                }
            }
            
            if (keyval == Gdk.Key.Up || keyval == Gdk.Key.Down) {
                return true;
            }
            
            return false;
        });
        
        text_view.text_view.cursor_moved.connect(() => {
            if (!session.is_after_prompt()) {
                text_view.text_view.cursor_line = session.prompt_line;
                text_view.text_view.cursor_col = session.prompt_col;
                text_view.text_view.queue_draw();
            }
        });
        
        var ctrl_handler = new Gtk.EventControllerKey();
        text_view.text_view.add_controller(ctrl_handler);
        
        ctrl_handler.key_pressed.connect((keyval, keycode, state) => {
            if ((state & Gdk.ModifierType.CONTROL_MASK) != 0 && keyval == Gdk.Key.c) {
                session.process.send_signal(Posix.Signal.INT);
                return true;
            }
            return false;
        });
    }

    private string get_current_command_line(AcmeTextView text_view, TerminalSession session) {
        if (text_view.text_view.cursor_line == session.prompt_line) {
            string line = text_view.text_view.lines[session.prompt_line];
            return line.substring(session.prompt_col, 
                                 text_view.text_view.cursor_col - session.prompt_col);
        } else {
            return text_view.text_view.lines[text_view.text_view.cursor_line];
        }
    }
    
    private void start_watch(string command, AcmeTextView text_view) {
        string watch_dir;
        string filename = text_view.get_filename();
        
        if (filename != "Untitled" && filename != "+Errors") {
            watch_dir = Path.get_dirname(filename);
        } else {
            watch_dir = Environment.get_current_dir();
        }
        
        foreach (var watcher in watchers) {
            if (watcher.target_view == text_view) {
                watcher.stop_watching();
                watchers.remove(watcher);
                break;
            }
        }
        
        var watcher = new AcmeFileWatcher(command, watch_dir, text_view);
        watchers.append(watcher);
        
        text_view.text_view.insert_text("Started watching " + watch_dir + " for changes\n");
        text_view.text_view.insert_text("Will execute: " + command + "\n\n");
    }
}