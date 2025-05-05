require 'sketchup.rb'
require 'base64'

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
    def self.get_explosion_entities(component, depth = 0)
      return [] if depth > 1  # limita a apenas uma camada de profundidade
    
      entities = component.definition.entities.select { |e|
        e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)
      }
    
      if entities.size == 1 && entities.first.is_a?(Sketchup::ComponentInstance)
        inner_component = entities.first
        return get_explosion_entities(inner_component, depth + 1)
      end
    
      entities
    end
    

    def self.move_doors_laterally(component, distance)
      portas = find_entities_on_layer(component, "Porta")
    
      # Bounding box do componente para determinar lateral e profundidade
      bounds = component.bounds
      largura = bounds.width
      profundidade = bounds.depth
      margem_extra_x = 50.cm
      margem_extra_y = 10.cm 
    
      # Deslocamento lateral: metade da largura + margem
      deslocamento_x = (largura / 2.0) + margem_extra_x
      deslocamento_y = (profundidade / 2.0) + margem_extra_y
    
      portas.each do |porta|
        offset = Geom::Vector3d.new(deslocamento_x, -deslocamento_y, 0)
        porta.set_attribute("MenegussiPlugin", "explosion_offset", [offset.x, offset.y, offset.z])
        porta.transform!(Geom::Transformation.translation(offset))
      end
    end
    
    

    def self.explode_selected(distance)
      model = Sketchup.active_model
      selection = model.selection
    
      if selection.count == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
        component = selection.first
        component.set_attribute("MenegussiPlugin", "last_explosion_distance", distance)
    
        # === Passo 1: Explodir entidades diretas ===
        entities = get_explosion_entities(component)
        center = component.bounds.center
    
        max_distance = entities.map { |e| center.distance(e.bounds.center) }.max
    
        entities.each do |entity|
          next unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    
          part_center = entity.bounds.center
          vector = center.vector_to(part_center)
          magnitude = vector.length
    
          scale_factor = magnitude / max_distance
          offset = vector.normalize.transform(distance * scale_factor)
    
          entity.set_attribute("MenegussiPlugin", "explosion_offset", [offset.x, offset.y, offset.z])
          entity.transform!(Geom::Transformation.translation(offset))
        end
    
        # === Passo 2: Explodir portas lateralmente, mesmo aninhadas ===
        def self.find_entities_on_layer(entity, layer_name, results = [])
          if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
            if entity.layer.name == layer_name
              results << entity
              return results  # Não continua recursão dentro da porta
            end
        
            ents = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
            ents.each { |child| find_entities_on_layer(child, layer_name, results) }
          end
          results
        end
    
      else
        UI.messagebox("Selecione um único componente.")
      end
    end
    
    
    
    # -------------------------------- Restaura o módulo a visualização original -----------------------
    def self.restore_entity_and_children(entity)
      return unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    
      offset_array = entity.get_attribute("MenegussiPlugin", "explosion_offset")
      if offset_array.is_a?(Array) && offset_array.size == 3
        offset_vector = Geom::Vector3d.new(offset_array)
        inverse_offset = offset_vector.reverse
        entity.transform!(Geom::Transformation.translation(inverse_offset))
        # entity.delete_attribute("MenegussiPlugin", "explosion_offset")  <--- comente esta linha
      end
    
      child_entities = entity.respond_to?(:definition) ? entity.definition.entities : entity.entities
      child_entities.each { |child| restore_entity_and_children(child) }
    end
    
    
    def self.restore_transforms
      model = Sketchup.active_model
      selection = model.selection
    
      if selection.count == 1 && selection.first.is_a?(Sketchup::ComponentInstance)
        component = selection.first
        restore_entity_and_children(component)
      else
        UI.messagebox("Selecione um único componente.")
      end
    end
    
    
    # ---------------------------------------- Função 2: Gerar Relatório --------------------------------

    # --------------------------------- Captura as imagens para o relatório -----------------------------


    def self.reapply_explosions(component)
      def self.reapply_offset_recursively(entity)
        if entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
          offset_array = entity.get_attribute("MenegussiPlugin", "explosion_offset")
          if offset_array.is_a?(Array) && offset_array.size == 3
            offset_vector = Geom::Vector3d.new(offset_array)
            entity.transform!(Geom::Transformation.translation(offset_vector))
          end
    
          # Reaplica nos filhos
          child_entities = if entity.respond_to?(:definition)
                             entity.definition.entities
                           else
                             entity.entities
                           end
    
          child_entities.each { |child| reapply_offset_recursively(child) }
        end
      end
    
      reapply_offset_recursively(component)
    end


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
    
      self.prepare_component_for_report(component)
    
      explosion_distance = component.get_attribute("MenegussiPlugin", "last_explosion_distance", 10.0)
    
      entities = component.definition.entities.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
    
      bounds = Geom::BoundingBox.new
      entities.each { |e| bounds.add(e.bounds) }
    
      center = bounds.center
      size = bounds.diagonal
      width = bounds.width
      height = bounds.height
      depth = bounds.depth
    
      # Usado para posicionamento de câmeras
      general_offset = [width, height, depth].max * 1.7
      cover_offset = [width, height, depth].max * 1.3
    
      image_paths = {}
    
      # === 0. Restaurar para gerar capa limpa ===
      self.restore_transforms
      self.clear_gbsflagged_texts(component)
    
      # === 1. Capa ISO limpa ===
      iso_eye = center.offset(Geom::Vector3d.new(-cover_offset * 0.3, -cover_offset * 1.2, cover_offset * 0.5))
      iso_cam_clean = Sketchup::Camera.new(iso_eye, center, [0, 0, 1], false)
      view.camera = iso_cam_clean
      view.refresh
      cover_path = File.join(Dir.tmpdir, "cover_iso.png")
      view.write_image(cover_path, 800, 600, true, 0)
    
      # === 1.1 Capa SEM portas ===
      door_layer = model.layers["Porta"]
      door_layer.visible = false if door_layer
      view.refresh
      cover_no_doors_path = File.join(Dir.tmpdir, "cover_iso_no_doors.png")
      view.write_image(cover_no_doors_path, 800, 600, true, 0)
      door_layer.visible = true if door_layer
    
      # === 2. Explosão + afastar portas ===
      self.reapply_explosions(component)
      self.move_doors_laterally(component, explosion_distance)
      self.generate_gbsflagged_texts(component)
    
      # === 3. ISO Explodido com portas ===
      exploded_entities = component.definition.entities.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }
      exploded_bounds = Geom::BoundingBox.new
      exploded_entities.each { |e| exploded_bounds.add(e.bounds) }

      exploded_center = exploded_bounds.center
      exploded_size = exploded_bounds.diagonal

      # Ajuste fino da distância da câmera
      exploded_cover_offset = exploded_size * 1.5  # Reduzido para aproximar

      # Vetor de deslocamento com ângulo melhor
      iso_exploded_eye = exploded_center.offset(Geom::Vector3d.new(
        -exploded_cover_offset * 0.6,   # Menos da lateral
        -exploded_cover_offset * 1.1,   # Frontal moderado
        exploded_cover_offset * 0.5     # Menos de cima
      ))

      iso_cam = Sketchup::Camera.new(iso_exploded_eye, exploded_center, [0, 0, 1], false)
      view.camera = iso_cam
      view.refresh
      iso_path = File.join(Dir.tmpdir, "preview_iso.png")
      view.write_image(iso_path, 800, 600, true, 0)
      image_paths["iso"] = iso_path

    
      # === 4. Restaurar componente para vistas frontais ===
      self.restore_transforms
      self.clear_gbsflagged_texts(component)
    
      # === 5. Vistas frontal e traseira ===
      front_cam = Sketchup::Camera.new(center.offset(Geom::Vector3d.new(0, -general_offset, 0)), center, [0, 0, 1], false)
      back_cam  = Sketchup::Camera.new(center.offset(Geom::Vector3d.new(0, general_offset, 0)),  center, [0, 0, 1], false)
    
      { "frente" => front_cam, "tras" => back_cam }.each do |nome, cam|
        view.camera = cam
        view.refresh
        path = File.join(Dir.tmpdir, "preview_#{nome}.png")
        view.write_image(path, 800, 600, true, 0)
        image_paths[nome] = path
      end
    
      # === 6. ISO por trás ===
      iso_behind_eye = center.offset(Geom::Vector3d.new(-cover_offset, cover_offset, cover_offset))
      iso_behind_cam = Sketchup::Camera.new(iso_behind_eye, center, [0, 0, 1], false)
      view.camera = iso_behind_cam
      view.refresh
      iso_behind_path = File.join(Dir.tmpdir, "preview_iso_behind.png")
      view.write_image(iso_behind_path, 800, 600, true, 0)
      image_paths["iso_behind"] = iso_behind_path
    
      # === 7. Vista de canto traseiro ===
      eye = component.bounds.corner(2).offset(Geom::Vector3d.new(20.cm, -10.cm, 20.cm))
      target = component.bounds.corner(0)
      corner_cam = Sketchup::Camera.new(eye, target, [0, 0, 1], false)
      view.camera = corner_cam
      view.refresh
      corner_path = File.join(Dir.tmpdir, "preview_corner.png")
      view.write_image(corner_path, 800, 600, true, 0)
      image_paths["corner"] = corner_path
    
      # === 8. Restaura a câmera original ===
      view.camera = original_camera
    
      # === 9. Metadados ===
      raw_name = component.definition.name
      clean_name = raw_name.gsub(/^\{\d+\.\d+\}\s*-\s*/, '')
      metadata = {
        "componente" => clean_name,
        "ambiente" => File.basename(model.path, ".skp")
      }
    
      [cover_no_doors_path, cover_path, image_paths, metadata]
    end
    
    
    
    # --------------------------------- Gerar ID's de montagem ------------------------------------------
    
    def self.prepare_component_for_report(component)
      definition = component.definition
      entities = definition.entities
    
      # === 1. Remover todos os textos existentes de forma recursiva ===
      def self.remove_all_texts_recursively(entities)
        entities.each do |ent|
          ent.erase! if ent.is_a?(Sketchup::Text)
    
          if ent.respond_to?(:definition) && ent.definition.respond_to?(:entities)
            remove_all_texts_recursively(ent.definition.entities)
          elsif ent.respond_to?(:entities)
            remove_all_texts_recursively(ent.entities)
          end
        end
      end
    
      remove_all_texts_recursively(entities)
    
      # === 2. Buscar por entidades com o atributo 'gbsflagged' de forma recursiva ===
      def self.collect_flagged_entities(entities, result = [])
        entities.each do |ent|
          if ent.respond_to?(:definition) && ent.definition.respond_to?(:entities)
            collect_flagged_entities(ent.definition.entities, result)
          elsif ent.respond_to?(:entities)
            collect_flagged_entities(ent.entities, result)
          end
    
          if ent.get_attribute("dynamic_attributes", "gbsflagged")
            result << ent
          end
        end
        result
      end
    
      flagged_entities = collect_flagged_entities(entities)
    
      # === 3. Adicionar textos com os valores de 'gbsflagged' acima das entidades ===
      flagged_entities.each do |ent|
        flag_value = ent.get_attribute("dynamic_attributes", "gbsflagged")
        next unless flag_value
    
        bounds = ent.bounds
        position = bounds.center.offset([0, 0, bounds.depth * 0.9])
        entities.add_text(flag_value.to_s, position)
      end
    end

    def self.clear_gbsflagged_texts(component)
      definition = component.definition
      entities = definition.entities
    
      def self.remove_all_texts_recursively(entities)
        entities.each do |ent|
          ent.erase! if ent.is_a?(Sketchup::Text)
    
          if ent.respond_to?(:definition) && ent.definition.respond_to?(:entities)
            remove_all_texts_recursively(ent.definition.entities)
          elsif ent.respond_to?(:entities)
            remove_all_texts_recursively(ent.entities)
          end
        end
      end
    
      remove_all_texts_recursively(entities)
    end
    
    def self.generate_gbsflagged_texts(component)
      definition = component.definition
      entities = definition.entities
    
      def self.collect_flagged_entities(entities, result = [])
        entities.each do |ent|
          if ent.respond_to?(:definition) && ent.definition.respond_to?(:entities)
            collect_flagged_entities(ent.definition.entities, result)
          elsif ent.respond_to?(:entities)
            collect_flagged_entities(ent.entities, result)
          end
    
          if ent.get_attribute("dynamic_attributes", "gbsflagged")
            result << ent
          end
        end
        result
      end
    
      flagged_entities = collect_flagged_entities(entities)
    
      flagged_entities.each do |ent|
        flag_value = ent.get_attribute("dynamic_attributes", "gbsflagged")
        next unless flag_value
    
        begin
          bounds = ent.bounds
          base_position = bounds.center
          z_offset = [bounds.depth * 0.9, 150.mm.to_f].max
          position = base_position.offset(Geom::Vector3d.new(0, 0, z_offset))
    
          entities.add_text(flag_value.to_s, position)
    
        rescue => e
          puts "Erro ao adicionar texto para entidade com 'gbsflagged': #{e.message}"
        end
      end
    end
    
    
    # ---------------------------- Pré-visualização do Relatório ----------------------------------------

    def self.show_report_preview
      cover_path, cover_no_doors_path, image_paths, metadata = self.capture_combined_views
    
      dialog = UI::HtmlDialog.new(
        dialog_title: "Pré-visualização do Relatório",
        width: 794,
        height: 1123,
        style: UI::HtmlDialog::STYLE_DIALOG
      )
    
      
      html_path = File.join(__dir__, "report_preview.html")
      html = File.read(html_path)

      footer_path = File.join(__dir__, "footer_logo.png")
      footer_data = File.binread(footer_path)
      footer_base64 = Base64.strict_encode64(footer_data)
      footer_src = "data:image/png;base64,#{footer_base64}"

      html.gsub!("{{FOOTER_IMAGE}}", footer_src)

    
      # Substituir os placeholders no HTML com os caminhos das imagens
      html.gsub!("{{COVER_IMAGE}}", "file:///#{cover_path.gsub("\\", "/")}")
      html.gsub!("{{COVER_IMAGE_2}}", "file:///#{cover_no_doors_path.gsub("\\", "/")}")
      html.gsub!("{{ISO_IMAGE}}", "file:///#{image_paths["iso"].gsub("\\", "/")}")
      html.gsub!("{{FRONT_IMAGE}}", "file:///#{image_paths["frente"].gsub("\\", "/")}")
      html.gsub!("{{BACK_IMAGE}}", "file:///#{image_paths["tras"].gsub("\\", "/")}")
      html.gsub!("{{BACK_ISO_IMAGE}}", "file:///#{image_paths["iso_behind"].gsub("\\", "/")}")
      html.gsub!("{{BACK_CORNER_IMAGE}}", "file:///#{image_paths["corner"].gsub("\\", "/")}")
      html.gsub!("{{NOME_COMPONENTE}}", metadata["componente"])
      html.gsub!("{{NOME_AMBIENTE}}", metadata["ambiente"])
    
      dialog.set_html(html)
      dialog.show
    end

    self.create_menu_and_toolbar
  end
end