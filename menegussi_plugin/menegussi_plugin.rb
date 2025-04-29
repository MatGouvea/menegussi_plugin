require 'sketchup.rb'

# ---------------------------------------- Inicio do plugin -------------------------------------------
module MenegussiPlugin
  module ExplodeTool

    @dialog = nil

    # ----------------------------------------- Gerar barra de ferramentas ----------------------------
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

      report_cmd = UI::Command.new("Gerar Relatório") {
        puts "Botão de relatório foi clicado"
        self.show_report_preview
      }


      # Ícone 
      icon_path = File.join(__dir__, "icon.png")
      if File.exist?(icon_path)
        cmd.small_icon = icon_path
        cmd.large_icon = icon_path
      end

      report_icon = File.join(__dir__, "report_icon.png") 
      if File.exist?(report_icon)
        report_cmd.small_icon = report_icon
        report_cmd.large_icon = report_icon
      end


      cmd.tooltip = "Explodir Componente"
      cmd.status_bar_text = "Visualizar partes do componente separadas."
      cmd.menu_text = "Explodir Componente"

      report_cmd.tooltip = "Gerar Relatório"
      report_cmd.status_bar_text = "Gera um relatório de montagem com o componente selecionado."
      report_cmd.menu_text = "Gerar Relatório"

      toolbar.add_item(report_cmd)
      toolbar.add_item(cmd)
      toolbar.show

      @ui_loaded = true
    end

    # ------------------------------------- Gerar interface do plugin ------------------------------------
    def self.open_ui
      # Evita abrir múltiplas instâncias
      if @dialog && @dialog.visible?
        @dialog.bring_to_front
        return
      end
    
      @dialog = UI::HtmlDialog.new(
        dialog_title: "Explodir Componente",
        width: 320,
        height: 200,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
    
      @dialog.set_file(File.join(__dir__, "ui.html"))
    
      @dialog.add_action_callback("explode") { |_, distance|
        self.explode_selected(distance.to_f)
      }
    
      @dialog.add_action_callback("restore") {
        self.restore_transforms
      }
    
      @dialog.show
    end
    

    # ------------------------------------- Função 1: Explodir Componente ------------------------------

    # ---------------------------------------------- Explodir módulo -----------------------------------
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
    
    # -------------------------------- Restaura o módulo a visualização original -----------------------
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
    
    # ---------------------------------------- Função 2: Gerar Relatório --------------------------------

    # --------------------------------- Captura as imagens para o relatório -----------------------------
    def self.create_camera(position_vector, target, up)
      Sketchup::Camera.new(target.offset(position_vector), target, up)
    end
    
    def self.capture_combined_views
      model = Sketchup.active_model
      view = model.active_view
      original_camera = view.camera
    
      selection = model.selection
      return unless selection.count == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
    
      component = selection.first
    
      # Calcular limites REAIS dos elementos internos (após explosão)
      entities = component.definition.entities.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      exploded_bounds = Geom::BoundingBox.new
      entities.each { |e| exploded_bounds.add(e.bounds) }
    
      center = exploded_bounds.center
      size = exploded_bounds.diagonal
      offset = size * 1.2
    
      image_paths = {}
    
      # === 1. Explodido - ISO ===
      iso_eye = center.offset(Geom::Vector3d.new(-offset * 0.5, -offset * 1.2, offset * 0.6))
      iso_cam = Sketchup::Camera.new(iso_eye, center, [0, 0, 1], true)
      view.camera = iso_cam
      view.refresh
      iso_path = File.join(Dir.tmpdir, "preview_iso.png")
      view.write_image(iso_path, 800, 600, true, 0)
      image_paths["iso"] = iso_path
    
      # === 2. Restaurar componente ===
      self.restore_transforms
    
      # === 3. Câmeras frontal e traseira — usando o mesmo bounds
      front_cam = Sketchup::Camera.new(center.offset(Geom::Vector3d.new(0, -offset, 0)), center, [0, 0, 1], true)
      back_cam  = Sketchup::Camera.new(center.offset(Geom::Vector3d.new(0, offset, 0)),  center, [0, 0, 1], true)
    
      {
        "frente" => front_cam,
        "tras" => back_cam
      }.each do |nome, cam|
        view.camera = cam
        view.refresh
        path = File.join(Dir.tmpdir, "preview_#{nome}.png")
        view.write_image(path, 800, 600, true, 0)
        image_paths[nome] = path
      end
    
      view.camera = original_camera
      image_paths
    end
    


    # ---------------------------- Pré-visualização do Relatório ----------------------------------------
    def self.show_report_preview
      image_paths = self.capture_combined_views

      dialog = UI::HtmlDialog.new(
        dialog_title: "Pré-visualização do Relatório",
        width: 794,
        height: 1123,
        style: UI::HtmlDialog::STYLE_DIALOG
      )


    
      html_path = File.join(__dir__, "report_preview.html")
      html = File.read(html_path)
    
      html.gsub!("{{ISO_IMAGE}}", "file:///#{image_paths["iso"].gsub("\\", "/")}")
      html.gsub!("{{FRONT_IMAGE}}", "file:///#{image_paths["frente"].gsub("\\", "/")}")
      html.gsub!("{{BACK_IMAGE}}", "file:///#{image_paths["tras"].gsub("\\", "/")}")
    
      dialog.set_html(html)
      dialog.show
    end
    
    
    



    self.create_menu_and_toolbar
  end
end
