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


      group_cmd = UI::Command.new("Agrupar Peças") {
        self.wrap_selection
      }

      assembly_cmd = UI::Command.new("Visualizar Componente") {
        self.show_viewer_window
      }
      
      icon = File.join(__dir__, "icon.png") 
      if File.exist?(icon)
        group_cmd.small_icon = icon
        group_cmd.large_icon = icon
      end

      group_icon = File.join(__dir__, "group_icon.png") 
      if File.exist?(group_icon)
        assembly_cmd.small_icon = group_icon
        assembly_cmd.large_icon = group_icon
      end

      group_cmd.tooltip = "Agrupar Componente"
      group_cmd.status_bar_text = "Agrupa o componente adequadamente para visualização."
      group_cmd.menu_text = "Agrupar Componente"

      assembly_cmd.tooltip = "Visualizar Componente"
      assembly_cmd.status_bar_text = "Abre a visualização do componente e etiquetas se disponíveis."
      assembly_cmd.menu_text = "Visualizar Componente"

      toolbar.add_item(group_cmd)
      toolbar.add_item(assembly_cmd)
      toolbar.show

      @ui_loaded = true
    end



    # ======================================= Agrupar Componente =================================


    def self.wrap_selection
      model = Sketchup.active_model
      sel   = model.selection
      ents  = model.active_entities

      if sel.empty?
        UI.messagebox('Selecione primeiro os elementos que deseja agrupar.')
        return
      end

      model.start_operation('Criar enterprise/voyager', true)
      begin
        # 1) Seleção → grupo → componente “voyager”
        g1       = ents.add_group(sel.to_a)
        voyager  = g1.to_component
        voyager.definition.name = 'voyager'

        # 2) Instância voyager → grupo → componente “enterprise”
        g2         = ents.add_group([voyager])
        enterprise = g2.to_component
        enterprise.definition.name = 'enterprise'

        # 3) Deixa só o enterprise selecionado (útil para mover logo depois)
        sel.clear
        sel.add(enterprise)

        model.commit_operation

      rescue => e
        model.abort_operation
        raise e
      end
    end
    


    # ======================================= Visualização =================================



    def self.show_viewer_window
      model = Sketchup.active_model
      sel = model.selection
      unless sel.length == 1 && (sel.first.is_a?(Sketchup::ComponentInstance) || sel.first.is_a?(Sketchup::Group))
        UI.messagebox("Selecione um componente ou grupo.")
        return
      end

      # Exportar geometria como JSON
      geometry = extract_groups(sel.first)

      # Criar a janela
      dlg = UI::HtmlDialog.new(
        dialog_title: "Visualizador de Componente",
        width: 1366,
        height: 735,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      # Enviar dados para o front-end
      html_path = File.join(__dir__, "viewer.html")
      dlg.set_file(html_path)
      dlg.add_action_callback("request_geometry") do |action_context|
        dlg.execute_script("loadGroupedGeometry(#{geometry.to_json})")
      end

      dlg.show
    end

    
    def self.traverse_entities(entities, parent_transform, triangles, parent_hidden = false)
      entities.each do |e|
        next if parent_hidden
        next if e.hidden?
        next if e.respond_to?(:layer) && !e.layer.visible?
    
        case e
        when Sketchup::Face
          mesh = e.mesh
          mesh.polygons.each do |poly|
            tri = poly.map do |index|
              pt = mesh.point_at(index.abs).transform(parent_transform)
              [pt.x.to_f, pt.y.to_f, pt.z.to_f]
            end
            triangles << tri if tri.size == 3
          end
        when Sketchup::ComponentInstance, Sketchup::Group
          combined_transform = parent_transform * e.transformation
          traverse_entities(e.definition.entities, combined_transform, triangles, parent_hidden)
        end
      end
    end
    

    
    def self.extract_groups(instance)
      voyager_root = find_voyager(instance)

      unless voyager_root
        UI.messagebox("Não foi encontrado um componente Gabster para começar.")
        return []
      end

      parts = []
      all_boxes_centers = []

      # Função auxiliar para converter de cm para mm
      def self.to_mm(value_cm)
        return nil if value_cm.nil?
        (value_cm.to_f * 10).round(2)
      end

      def self.inches_to_mm(value_in)
        return nil if value_in.nil?
        (value_in.to_f * 25.4).round(2)
      end

      # Função auxiliar para coletar atributos GBS e medidas
      get_gbs_attributes = lambda do |entity, level|
        if entity.respond_to?(:attribute_dictionaries)
          if level == "voyager"
            {
              gbsflagged: entity.get_attribute("dynamic_attributes", "gbsflagged"),
              gbsref:     entity.get_attribute("dynamic_attributes", "gbsref"),
              gbsx:       inches_to_mm(entity.get_attribute("dynamic_attributes", "limite_x")),
              gbsy:       inches_to_mm(entity.get_attribute("dynamic_attributes", "limite_y")),
              gbsz:       inches_to_mm(entity.get_attribute("dynamic_attributes", "limite_z"))
            }
          else
            {
              gbsflagged: entity.get_attribute("dynamic_attributes", "gbsflagged"),
              gbsref:     entity.get_attribute("dynamic_attributes", "gbsref"),
              gbsx:       to_mm(entity.get_attribute("dynamic_attributes", "gbsx")),
              gbsy:       to_mm(entity.get_attribute("dynamic_attributes", "gbsy")),
              gbsz:       to_mm(entity.get_attribute("dynamic_attributes", "gbsz"))
            }
          end
        else
          { gbsflagged: nil, gbsref: nil, gbsx: nil, gbsy: nil, gbsz: nil }
        end
      end




      # Adiciona geometrias do nível raiz (exceto 'enterprise')
      instance.definition.entities.each do |e|
        next if e.hidden?
        next if e.respond_to?(:layer) && e.layer.name.downcase == "enterprise"
        next unless e.is_a?(Sketchup::ComponentInstance) || e.is_a?(Sketchup::Group)

        next if find_voyager(e)

        triangles = []
        transform = instance.transformation * e.transformation
        traverse_entities(e.definition.entities, transform, triangles)

        unless triangles.empty?
          box = e.bounds
          transformed_box = Geom::BoundingBox.new
          8.times { |i| transformed_box.add(box.corner(i).transform(transform)) }
          all_boxes_centers << transformed_box.center.to_a

          attrs = get_gbs_attributes.call(e, "root")

          parts << {
            hidden: false,
            triangles: triangles,
            gbsflagged: attrs[:gbsflagged],
            gbsref: attrs[:gbsref],
            gbsx: attrs[:gbsx],
            gbsy: attrs[:gbsy],
            gbsz: attrs[:gbsz],
            level: "root"
          }

        end
      end

      # Adiciona as geometrias do voyager
      voyager_root.definition.entities.each do |child|
        next unless child.is_a?(Sketchup::ComponentInstance) || child.is_a?(Sketchup::Group)

        
        next if child.hidden?
        next if child.respond_to?(:layer) && !child.layer.visible?

        voyager_flag = voyager_root.get_attribute("dynamic_attributes", "gbsgroup")

        triangles = []
        transform = instance.transformation * voyager_root.transformation * child.transformation
        traverse_entities(child.definition.entities, transform, triangles)

        unless triangles.empty?
          original_box = child.bounds
          transformed_box = Geom::BoundingBox.new
          8.times { |i| transformed_box.add(original_box.corner(i).transform(transform)) }
          all_boxes_centers << transformed_box.center.to_a

          attrs = get_gbs_attributes.call(child, "voyager")

          parts << {
            hidden: false,
            triangles: triangles,
            gbsflagged: voyager_flag || attrs[:gbsflagged],
            gbsref: attrs[:gbsref],
            gbsx: attrs[:gbsx],
            gbsy: attrs[:gbsy],
            gbsz: attrs[:gbsz],
            level: "voyager"
          }
        end
      end

      # Centro médio
      if all_boxes_centers.empty?
        voyager_center = [0, 0, 0]
      else
        sum = all_boxes_centers.transpose.map { |axis| axis.sum }
        voyager_center = sum.map { |v| v / all_boxes_centers.size }
      end

      {
        parts: parts,
        origin: voyager_center
      }
    end



    def self.find_voyager(entity)
      if entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
        def_name = entity.definition.name.downcase
        return entity if def_name.include?('voyager')

        entity.definition.entities.each do |child|
          next unless child.is_a?(Sketchup::ComponentInstance) || child.is_a?(Sketchup::Group)
          result = find_voyager(child)
          return result if result
        end
      end

      nil
    end

    
    
    self.create_menu_and_toolbar
  end
end