project('com.example.valacme', ['c', 'vala'], version: '0.1.0')

# Convert the app id to a GNOME style path identifier
path_identifier = '/' + meson.project_name().replace('.', '/') + '/'

gnome = import('gnome')
i18n = import('i18n')

subdir('data')
subdir('src')

gnome.post_install(
    glib_compile_schemas: true,
    gtk_update_icon_cache: true,
    update_desktop_database: true,
)
