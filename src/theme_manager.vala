/* theme_manager.vala
 * Centralized theme management
 */

public class AcmeThemeManager : Object {
    private static AcmeThemeManager? instance;
    private Gtk.CssProvider provider;
    
    // Acme color constants
    private const string TAG_BACKGROUND = "#E9FFFE";      // Light cyan for tags
    private const string BORDER_COLOR = "#000";          // Black for borders
    private const string WINDOW_BORDER_COLOR = "#8888cc"; // Dark blue for window borders
    private const string SCROLLBAR_COLOR = "#99994c";    // Olive for scrollbars
    private const string SCROLLBAR_SLIDER = "#ffffea";   // Light yellow for slider
    
    private AcmeThemeManager() {
        provider = new Gtk.CssProvider();
        setup_css();
    }
    
    public static AcmeThemeManager get_instance() {
        if (instance == null) {
            instance = new AcmeThemeManager();
        }
        return instance;
    }
    
    private void setup_css() {
        // Build CSS string with constants
        string css = build_theme_css();
        
        provider.load_from_string(css);
        
        // Apply globally
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }
    
    private string build_theme_css() {
        return """
            /* Global reset */
            * {
              margin: 0;
              padding: 0;
              box-shadow: none;
              border: none;
              outline: none;
              color: #000;
              min-height: 16px;
              font-size: 16px;
            }
            
            window {
              background: #FFF;
            }
            
            /* Scrollbar styling */
            scrollbar {
              margin-right: -12px;
              min-width: 11px;
              border: none;
              border-right: 1px solid """ + SCROLLBAR_COLOR + """;
              box-shadow: none;
              background: """ + SCROLLBAR_COLOR + """;
            }
            
            scrollbar trough {
              min-width: 11px;
              border-radius: 0;
              border: none;
              box-shadow: none;
            }
            
            scrollbar slider {
              min-width: 11px;
              border-radius: 0;
              border: none;
              box-shadow: none;
              background: """ + SCROLLBAR_SLIDER + """;
            }
            
            /* Tag bar styles */
            .acme-main-tag {
              padding-left: 16px;
              background: """ + TAG_BACKGROUND + """;
              border-bottom: 2px solid """ + BORDER_COLOR + """;
            }
            
            .acme-column-header {
              background: """ + TAG_BACKGROUND + """;
              border-bottom: 2px solid """ + BORDER_COLOR + """;
            }
            
            .acme-tag {
              background: """ + TAG_BACKGROUND + """;
              border-bottom: 1px solid """ + WINDOW_BORDER_COLOR + """;
            }
            
            /* Column borders */
            .acme-column {
              border-right: none;
            }
            
            .acme-column-interior {
              border-right: 2px solid """ + BORDER_COLOR + """;
            }
            
            .acme-column-rightmost {
              border-right: none;
            }
            
            .acme-text-window {
              border-top: none;
            }
            
            .acme-text-window:not(:first-child) {
              border-top: 2px solid """ + BORDER_COLOR + """;
            }
            
            /* Text elements */
            textview {
              border: none;
            }
            
            scrolledwindow {
              border: none;
            }
            
            /* Minimum heights */
            .acme-column-header, .acme-tag, .acme-main-tag {
              min-height: 18px;
            }
        """;
    }
    
    /**
     * Apply column border styling based on position
     */
    public void apply_column_border_style(Gtk.Widget column, bool is_rightmost) {
        // Ensure base class is present
        column.add_css_class("acme-column");
        
        // Remove existing position classes
        column.remove_css_class("acme-column-interior");
        column.remove_css_class("acme-column-rightmost");
        
        // Apply appropriate class
        if (is_rightmost) {
            column.add_css_class("acme-column-rightmost");
        } else {
            column.add_css_class("acme-column-interior");
        }
    }
    
    /**
     * Apply text view styling
     */
    public void apply_text_style(Gtk.TextView text_view) {
        text_view.add_css_class("acme-text");
    }
    
    // Color accessors for programmatic use
    public static Gdk.RGBA get_tag_background_color() {
        Gdk.RGBA color = Gdk.RGBA();
        color.parse(TAG_BACKGROUND);
        return color;
    }
    
    public static Gdk.RGBA get_border_color() {
        Gdk.RGBA color = Gdk.RGBA();
        color.parse(BORDER_COLOR);
        return color;
    }
    
    public static Gdk.RGBA get_window_border_color() {
        Gdk.RGBA color = Gdk.RGBA();
        color.parse(WINDOW_BORDER_COLOR);
        return color;
    }
}