require 'sketchup.rb'

module MenegussiPlugin
  module ExplodeTool

    def self.create_menu_and_toolbar
      return if @ui_loaded

      # Menu
      UI.menu("Plugins").add_item("Explodir Componente") {
        self.open_ui
      }

      # Toolbar
      toolbar = UI::Toolbar.new("Menegussi Plugin")

      cmd = UI::Command.new("Explodir Componente") {
        self.open_ui
      }

      # Ícone (opcional)
      icon_path = File.join(__dir__, "icon.png")
      if File.exist?(icon_path)
        cmd.small_icon = icon_path
        cmd.large_icon = icon_path
      end

      cmd.tooltip = "Explodir Componente"
      cmd.status_bar_text = "Visualizar partes do componente separadas"
      cmd.menu_text = "Explodir Componente"

      toolbar.add_item(cmd)
      toolbar.show

      @ui_loaded = true
    end

    def self.open_ui
      html = UI::HtmlDialog.new(
        dialog_title: "Explodir Componente",
        width: 300,
        height: 180,
        style: UI::HtmlDialog::STYLE_DIALOG
      )


      html.set_file(File.join(__dir__, "ui.html"))

      html.add_action_callback("explode") { |_, distance|
        self.explode_selected(distance.to_f)
      }
      html.add_action_callback("restore") {
       self.restore_transforms
      }

      html.show
    end

    def self.explode_selected(distance)
      model = Sketchup.active_model
      selection = model.selection
    
      if selection.count == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
        component = selection.first
        entities = component.definition.entities
        center = component.bounds.center
    
        # Maior distância do centro até qualquer parte — para normalizar
        max_distance = entities.map { |e|
          center.distance(e.bounds.center)
        }.max
    
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    
          part_center = entity.bounds.center
          vector = center.vector_to(part_center)
          magnitude = vector.length
    
          # Fator proporcional à distância do centro
          scale_factor = magnitude / max_distance
          offset = vector.normalize.transform(distance * scale_factor)
    
          # Salva apenas o último offset
          entity.set_attribute("MenegussiPlugin", "explosion_offset", [offset.x, offset.y, offset.z])
    
          # Aplica transformação
          entity.transform!(Geom::Transformation.translation(offset))
        end
      else
        UI.messagebox("Selecione um único componente.")
      end
    end
    
    
    

    def self.restore_transforms
      model = Sketchup.active_model
      selection = model.selection
    
      if selection.count == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
        component = selection.first
        entities = component.definition.entities
    
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    
          offset_array = entity.get_attribute("MenegussiPlugin", "explosion_offset")
          next unless offset_array.is_a?(Array) && offset_array.size == 3
    
          # Cria vetor a partir do offset salvo
          offset_vector = Geom::Vector3d.new(offset_array)
          inverse_offset = offset_vector.reverse
          entity.transform!(Geom::Transformation.translation(inverse_offset))
    
          # Limpa o atributo após restaurar
          entity.delete_attribute("MenegussiPlugin", "explosion_offset")
        end
      else
        UI.messagebox("Selecione um único componente.")
      end
    end
    
    

    self.create_menu_and_toolbar
  end
end
