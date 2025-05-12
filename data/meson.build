gresources = gnome.compile_resources(
    'resources',
    configure_file(
        input: 'gresource.xml.in',
        output: meson.project_name() + '.gresource.xml',
        configuration: {
            'APP_ID': meson.project_name(),
            'APP_PATH': path_identifier,
        },
    ),
    source_dir: meson.current_build_dir(),
    c_name: 'resources',
    install_dir: get_option('datadir') / meson.project_name(),
)

add_project_arguments(
    '--gresourcesdir',
    meson.current_build_dir(),
    language: ['vala'],
)

desktop_file = i18n.merge_file(
    input: configure_file(
        input: 'app.desktop.in.in',
        output: meson.project_name() + '.desktop.in',
        configuration: {
            'ICON_NAME': meson.project_name(),
            'COMMAND': meson.project_name(),
        },
    ),
    output: meson.project_name() + '.desktop',
    po_dir: meson.project_source_root() / 'po',
    type: 'desktop',
    install: true,
    install_dir: get_option('datadir') / 'applications',
)

desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
    test('validate-desktop', desktop_file_validate, args: [desktop_file])
endif

subdir('icons')
