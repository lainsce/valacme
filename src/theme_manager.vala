/* theme_manager.vala
 * Centralized theme management
 */

public class AcmeThemeManager : Object {
    private static AcmeThemeManager? instance;
    private Gtk.CssProvider provider;
    
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
        // Acme uses these exact colors
        string tag_background = "#E9FFFE";         // Light cyan for tags
        string border_color = "#000";              // Black for borders
        string window_border_color = "#8888cc";    // Dark blue for win borders

        provider.load_from_string("""
            /* Reset everything */
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
            scrollbar {
              margin-right: -12px; /* Fix UI bug */
              min-width: 11px;
              border: none;
              border-right: 1px solid #99994c;
              box-shadow: none;
              background: #99994c;
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
              background: #ffffea;
            }
            /* Main tag style */
            .acme-main-tag {
              padding-left: 16px;
              background: """ + tag_background + """;
              border-bottom: 2px solid """ + border_color + """;
            }
            
            /* Column tag style */
            .acme-column-header {
              background: """ + tag_background + """;
              border-bottom: 2px solid """ + border_color + """;
            }
            
            /* Window tag style */
            .acme-tag {
              background: """ + tag_background + """;
              border-bottom: 1px solid """ + window_border_color + """;
            }
            
            .acme-column {
              /* No default border */
              border-right: none;
            }
            
            /* Interior columns only */
            .acme-column-interior {
              border-right: 2px solid """ + border_color + """;
            }
            
            /* Rightmost column specifically has no border */
            .acme-column-rightmost {
              border-right: none;
            }
            
            textview {
              border: none;
            }
            
            scrolledwindow {
              border: none;
            }
            
            .acme-column-header, .acme-tag, .acme-main-tag {
              min-height: 16px;
            }
        """);
        
        // While Gtk.StyleContext is deprecated in GTK 4.10, we need to use it for compatibility
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(),
            provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
    }
    
    /* Apply specific styles to widgets that need direct styling */
    public void apply_text_style(Gtk.TextView text_view) {
        text_view.add_css_class("acme-text");
    }
    
    /**
     * Apply column border styling based on position
     * @param column The column to style
     * @param is_rightmost Whether this is the rightmost column
     */
    public void apply_column_border_style(Gtk.Widget column, bool is_rightmost) {
        // Make sure it has the base column class
        column.add_css_class("acme-column");
        
        // Remove any existing position-specific classes
        column.remove_css_class("acme-column-interior");
        column.remove_css_class("acme-column-rightmost");
        
        // Apply the appropriate class based on position
        if (is_rightmost) {
            column.add_css_class("acme-column-rightmost");
        } else {
            column.add_css_class("acme-column-interior");
        }
    }
}