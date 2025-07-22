require 'sketchup.rb'
require 'extensions.rb'

module MenegussiPlugin
  PLUGIN_NAME = 'Menegussi Plugin'
  PLUGIN_PATH = File.join(__dir__, 'menegussi_plugin', 'menegussi_plugin.rb')

  extension = SketchupExtension.new(PLUGIN_NAME, PLUGIN_PATH)
  extension.version = '1.0.0'
  extension.description = 'Explode visualmente um componente para mostrar suas partes.'
  extension.creator = 'Matheus Gouvea'

  Sketchup.register_extension(extension, true)
end
