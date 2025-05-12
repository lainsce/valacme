add_project_arguments(
  '-w',
  '-DGETTEXT_PACKAGE="@0@"'.format(meson.project_name()),
  language: 'c',
)

sources = [
  gresources,
  'main.vala',
  'window.vala',
  'textview.vala',
  'textwidget.vala',
  'column.vala',
  'plumber.vala',
  'filehandler.vala',
  'search.vala',
  'editcommand.vala',
  'theme_manager.vala',
  'command_manager.vala',
  'ui_helper.vala',
]

dependencies = [
  dependency('gtk4'),
  dependency('glib-2.0'),
  dependency('gobject-2.0'),
  dependency('gio-2.0'),
  dependency('gee-0.8'),
  dependency('gmodule-2.0'),
  dependency('gio-unix-2.0'), # For Unix-specific functionality like Subprocess
  meson.get_compiler('vala').find_library('posix', required: true),
  meson.get_compiler('c').find_library('m', required: true),
]

executable(
  meson.project_name(),
  sources,
  dependencies: dependencies,
  install: true,
)
