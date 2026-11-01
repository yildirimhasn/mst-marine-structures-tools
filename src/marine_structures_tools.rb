# frozen_string_literal: true
require 'sketchup.rb'
require 'extensions.rb'
require_relative 'marine_structures_tools/qto_workspace'
module MAG
  module MarineStructuresTools
    EXTENSION=SketchupExtension.new('Deniz Yapıları Araçları (MST)','marine_structures_tools/main')
    EXTENSION.description='Gerçek proje kotlarıyla parametrik deniz yapıları modelleme ve metraj araçları.'
    EXTENSION.version=VERSION
    EXTENSION.creator='MAG / Marine Structures Tools'
    Sketchup.register_extension(EXTENSION,true)
  end
end
