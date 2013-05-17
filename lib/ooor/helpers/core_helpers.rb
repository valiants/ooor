#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Akretion: Raphaël Valyi: CampToCamp: Nicolas Bessi, Joel Grand-Guillaume
#    Licensed under the MIT license, see MIT-LICENSE file

Ooor.xtend('ir.module.module') do

  ##########################################################################
  # Get recursively the whole list of modules dependencies
  # for a list of modules.
  # Do not add the module if it already exists in the input list
  # Input :
  #  - modules : A [] of valid IrModuleModule instances with dependencies_id attribute
  # Return
  #  -  [] of dependencies
  # Usage Example:
  # dependency_modules = get_dependencies(modules)
  def self.get_dependencies(modules)
    dependency_modules = []
    modules.select { |m| m.dependencies_id }.each do |mod|
      mod.dependencies_id.each do |dep|
        dep_module = IrModuleModule.find(:first,
                                         :domain => [['name', '=', dep.name]],
                                         :fields => ['id', 'state', 'dependencies_id'])
        if dep_module.nil?
          raise RuntimeError, "#{dep.name} not found"
        end
        dependency_modules << dep_module unless (modules + dependency_modules).map { |m| m.id }.include? dep_module.id
      end
    end
    dependency_modules.concat(get_dependencies(dependency_modules)) if dependency_modules.count > 0
    dependency_modules.uniq { |m| m.id }
  end
  
  ##########################################################################
  # Run the upgrade wizard in order to install the required
  # modules. Upgrade installed modules as well.
  # Input :
  #  - modules : A [] of valid IrModuleModule instance
  # Return
  #  - True
  # Usage Example:
  # res = IrModuleModule.install_modules(@openerp, modules)
  def self.install_modules(modules, dependencies=false)
    res = true
    if dependencies
      dependency_modules = get_dependencies(modules)
      modules.concat(dependency_modules) if dependency_modules
    end
    modules_toinstall_ids = []
    modules_toupgrade_ids = []
    # If not installed, do it. Otherwise update it
    modules.each do |m|
      if m.state == 'uninstalled'
        m.state = 'to install'
        m.save
        modules_toinstall_ids << m.id
      elsif m.state == 'installed'
        m.state = 'to upgrade'
        m.save
        modules_toupgrade_ids << m.id
      elsif m.state == 'to install'
        modules_toinstall_ids << m.id
      elsif m.state == 'to upgrade'
        modules_toupgrade_ids << m.id
      end
    end
    #First installed required modules, then upgrade the others
    upgrade = BaseModuleUpgrade.create()
    upgrade.upgrade_module()
    # IrModuleModule.button_install(modules_toinstall_ids)
    # IrModuleModule.button_upgrade(modules_toupgrade_ids)

    if res
      return true
    else
      raise "!!! --- HELPER ERROR : install_modules was unable to install needed modules.."
    end
    openerp.load_models() # reload in order to have model Classes for modules installed
  end
  
  def print_uml
    l = IrModelData.find(:all, :domain => {:model=>"ir.model", :module=>name})
    model_names = []
    l.each {|i| model_names << i.name.gsub('_', '.').gsub(/^model.report/, '').gsub(/^model./, '')}
    classes = []
    model_names.each {|i| begin classes << Object.const_get(IrModel.class_name_from_model_key i); rescue; end}
    classes.reject! {|m| m.openerp_model.index("report")} #NOTE we would need a more robust test
    begin
      classes.reject! {|m| IrModel.read(m.openerp_id, ['osv_memory'])['osv_memory']}
    rescue
    end
    classes.reject! {|m| m.openerp_model == "res.company"} if classes.size > 10
    OoorDoc::UML.print_uml(classes, {:file_name => "#{name}_uml"})
  end

  def print_dependency_graph
    modules = [self] + self.class.get_dependencies([self])

    File.open("#{self.name}-pre.dot", 'w') do |f|
      f << <<-eos
      digraph DependenciesByOOOR {
          fontname = "Helvetica"
          fontsize = 11
          label = "*** generated by OOOR by www.akretion.com ***"
          node [
                  fontname = "Helvetica"
                  fontsize = 11
                  shape = "record"
                  fillcolor=orange
                  style="rounded,filled"
          ]
      eos

      modules.each do |m|
        m.dependencies_id.each do |dep|
          f << "#{m.name} -> #{dep.name};\n"
        end
      end
      f << "}"
    end
    system("tred < #{self.name}-pre.dot > #{self.name}.dot")
    cmd_line2 = "dot -Tcmapx -o#{self.name}.map -Tpng -o#{self.name}.png #{self.name}.dot"
    system(cmd_line2)
      
  end
    
end


Ooor.xtend('ir.ui.menu') do
  def menu_action
    #TODO put in cache eventually:
    action_values = self.class.ooor.const_get('ir.values').rpc_execute('get', 'action', 'tree_but_open', [['ir.ui.menu', id]], false, self.class.ooor.connection_session)[0][2]#get already exists
    @menu_action = self.class.ooor.const_get('ir.actions.act_window').new(action_values, []) #TODO deal with action reference instead
  end
end
