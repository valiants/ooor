#    OOOR: OpenObject On Ruby
#    Copyright (C) 2009-2012 Akretion LTDA (<http://www.akretion.com>).
#    Author: Raphaël Valyi
#    Licensed under the MIT license, see MIT-LICENSE file

require File.dirname(__FILE__) + '/../lib/ooor'

#RSpec executable specification; see http://rspec.info/ for more information.
#Run the file with the rspec command  from the rspec gem
describe Ooor do
  before(:all) do
    @url = 'http://localhost:8069/xmlrpc'
    @db_password = 'admin'
    @username = 'admin'
    @password = 'admin'
    @database = 'ooor_test'
    @ooor = Ooor.new(:url => @url, :username => @username, :password => @password)
  end

  it "should keep quiet if no database is mentioned" do
    @ooor.loaded_models.should be_empty
  end

  it "should be able to list databases" do
    @ooor.list.should be_kind_of(Array) 
  end

  it "should be able to create a new database with demo data" do
    unless @ooor.list.index(@database)
      @ooor.create(@db_password, @database)
    end
    @ooor.list.index(@database).should_not be_nil
  end

  
  describe "Configure existing database" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database)
    end

    it "should be able to load a profile" do
      module_ids = IrModuleModule.search(['name','=', 'sale']) + IrModuleModule.search(['name','=', 'account_voucher']) + IrModuleModule.search(['name','=', 'sale_stock'])
      module_ids.each do |accounting_module_id|
        mod = IrModuleModule.find(accounting_module_id) 
        unless mod.state == "installed"
          mod.button_install
        end
      end
      wizard = BaseModuleUpgrade.create
      wizard.upgrade_module
      @ooor.load_models
#          config5 = AccountInstaller.create(:charts => 'configurable')
#          config5.action_next
      @ooor.loaded_models.should_not be_empty
    end

    it "should be able to configure the database" do
#      chart_module_id = IrModuleModule.search([['category_id', '=', 'Account Charts'], ['name','=', 'l10n_fr']])[0]
      if AccountTax.search.empty?
        w1 = @ooor.const_get('account.installer').create(:charts => "configurable")
        w1.action_next
        w1 = @ooor.const_get('wizard.multi.charts.accounts').create(:charts => "configurable", :code_digits => 2)
        w1.action_next
#        w3 = @ooor.const_get('wizard.multi.charts.accounts').create
#        w3.action_create
      end
    end
  end


  describe "Do operations on configured database" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database,
        :models => ['res.user', 'res.partner', 'product.product',  'sale.order', 'account.invoice', 'product.category', 'stock.move', 'ir.ui.menu'])
    end

    describe "Finders operations" do

      it "should be able to find data by id" do
        p = ProductProduct.find(1)
        p.should_not be_nil
        p = ProductProduct.find(:first)
        p.should_not be_nil
        l = ProductProduct.find([1,2])
        l.size.should == 2
      end

      it "should load required models on the fly" do
        SaleOrder.find(1).shop_id.should be_kind_of(SaleShop)
      end

      it "should be able to specify the fields to read" do
        p = ProductProduct.find(1, :fields=>["state", "id"])
        p.should_not be_nil
      end

      it "should be able to find using ir.model.data absolute ids" do
        p = ResPartner.find('res_partner_1')
        p.should_not be_nil
        p = ResPartner.find('base.res_partner_1')#module scoping is optionnal
        p.should_not be_nil
      end

      it "should be able to use OpenERP domains" do
        partners = ResPartner.find(:all, :domain=>[['supplier', '=', 1],['active','=',1]], :fields=>["id", "name"])
        partners.should_not be_empty
        products = ProductProduct.find(:all, :domain=>[['categ_id','=',1],'|',['name', '=', 'PC1'],['name','=','PC2']])
        products.should be_kind_of(Array)
      end

      it "should mimic ActiveResource scoping" do
        partners = ResPartner.find(:all, :params => {:supplier => true})
        partners.should_not be_empty
      end

      it "should mimic ActiveResource scopinging with first" do
        partner = ResPartner.find(:first, :params => {:customer => true})
        partner.should be_kind_of ResPartner
      end

      it "should support OpenERP context in finders" do
        p = ProductProduct.find(1, :context => {:my_key => 'value'})
        p.should_not be_nil
        products = ProductProduct.find(:all, :context => {:lang => 'es_ES'})
        products.should be_kind_of(Array)
      end

      it "should support OpenERP search method" do
        partners = ResPartner.search([['name', 'ilike', 'a']], 0, 2)
        partners.should_not be_empty
      end

      it "should cast dates properly from OpenERP to Ruby" do
        o = SaleOrder.find(1)
        o.date_order.should be_kind_of(Date)
        m = StockMove.find(1)
        m.date.should be_kind_of(DateTime)
      end

      it "should be able to call any Class method" do
        ResPartner.name_search('ax', [], 'ilike', {}).should_not be_nil
      end

    end

    describe "Relations reading" do
      it "should read many2one relations" do
        o = SaleOrder.find(1)
        o.partner_id.should be_kind_of(ResPartner)
        p = ProductProduct.find(1) #inherited via product template
        p.categ_id.should be_kind_of(ProductCategory)
      end

      it "should read one2many relations" do
        o = SaleOrder.find(1)
        o.order_line.each do |line|
        line.should be_kind_of(SaleOrderLine)
        end
      end

      it "should read many2many relations" do
        s = SaleOrder.find(1)
        s.order_policy = 'manual'
        s.save
        s.wkf_action('order_confirm')
        s.wkf_action('manual_invoice')
        SaleOrder.find(1).order_line[1].invoice_lines.should be_kind_of(Array)
      end

      it "should read polymorphic references" do
        IrUiMenu.find(:first, :domain => [['name', '=', 'Customers'], ['parent_id', '!=', false]]).action.should be_kind_of(IrActionsAct_window)
      end
    end

    describe "Basic creations" do
      it "should be able to assign a value to an unloaded field" do
        p = ProductProduct.new
        p.name = "testProduct1"
        p.name.should == "testProduct1"
      end

      it "should be able to create a product" do
        p = ProductProduct.create(:name => "testProduct1", :categ_id => 1)
        ProductProduct.find(p.id).categ_id.id.should == 1
        p = ProductProduct.new(:name => "testProduct1")
        p.categ_id = 1
        p.save
        p.categ_id.id.should == 1
      end

      it "should support read on new objects" do
        u = ResUsers.new({name: "joe", login: "joe"})
        u.id.should be_nil
        u.name.should == "joe"
        u.email.should == nil
        u.save
        u.id.should_not be_nil
        u.name.should == "joe"
        u.destroy
      end

      it "should support the context at object creation" do
        p = ProductProduct.new({:name => "testProduct1", :categ_id => 1}, false, {:lang => 'en_US', :ooor_user_id=>1, :ooor_password => 'admin'})
        p.object_session[:lang].should == 'en_US'
        p.object_session[:ooor_user_id].should == 1
        p.object_session[:ooor_password].should == "admin"
        p.save
      end

      it "should support context when instanciating collections" do
        products = ProductProduct.find([1, 2, 3], :context => {:lang => 'en_US', :ooor_user_id=>1, :ooor_password => 'admin'})
        p = products[0]
        p.object_session[:lang].should == 'en_US'
        p.object_session[:ooor_user_id].should == 1
        p.object_session[:ooor_password].should == "admin"
        p.save
      end

      it "should be able to create an order" do
        o = SaleOrder.create(:partner_id => ResPartner.search([['name', 'ilike', 'Agrolait']])[0], 
          :partner_order_id => 1, :partner_invoice_id => 1, :partner_shipping_id => 1, :pricelist_id => 1)
        o.id.should be_kind_of(Integer)
      end

      it "should be able to to create an invoice" do
        i = AccountInvoice.new(:origin => 'ooor_test')
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        i.on_change('onchange_partner_id', :partner_id, partner_id, 'out_invoice', partner_id, false, false)
        i.save
        i.id.should be_kind_of(Integer)
      end

      it "should be able to call on_change" do
        o = SaleOrder.new
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        o.on_change('onchange_partner_id', :partner_id, partner_id, partner_id)
        o.save
        line = SaleOrderLine.new(:order_id => o.id)
        product_id = 1
        pricelist_id = 1
        product_uom_qty = 1
        line.on_change('product_id_change', :product_id, product_id, pricelist_id, product_id, product_uom_qty, false, 1, false, false, o.partner_id.id, 'en_US', true, false, false, false)
        line.save
        SaleOrder.find(o.id).order_line.size.should == 1
      end

      it "should use default fields on creation" do
        p = ProductProduct.new
        p.sale_delay.should be_kind_of(Integer)
      end

      it "should skipped inherited default fields properly, for instance at product variant creation" do
        #note that we force [] here for the default_get_fields otherwise OpenERP will blows up while trying to write in the product template!
        ProductProduct.create({:product_tmpl_id => 25, :code => 'OOOR variant'}, {}, []).should be_kind_of(ProductProduct)
      end
    end

    describe "Basic updates" do
      it "should cast properly from Ruby to OpenERP" do
        o = SaleOrder.find(1).copy()
        o.date_order = 2.days.ago
        o.save
      end

      it "should be able to reload resource" do
        s = SaleOrder.find(1)
        s.reload.should be_kind_of(SaleOrder)
      end
    end

    describe "Relations assignations" do
      it "should be able to assign many2one relations on new" do
        new_partner_id = ResPartner.search()[0]
        s = SaleOrder.new(:partner_id => new_partner_id)
        s.partner_id.id.should == new_partner_id
      end

      it "should be able to do product.taxes_id = [id1, id2]" do
        p = ProductProduct.find(1)
        p.taxes_id = AccountTax.search([['type_tax_use','=','sale']])[0..1]
        p.save
        p.taxes_id[0].should be_kind_of(AccountTax)
        p.taxes_id[1].should be_kind_of(AccountTax)
      end

      it "should be able to create one2many relations on the fly" do
        so = SaleOrder.new
        partner_id = ResPartner.search([['name', 'ilike', 'Agrolait']])[0]
        so.on_change('onchange_partner_id', :partner_id, partner_id, partner_id) #auto-complete the address and other data based on the partner
        so.order_line = [SaleOrderLine.new(:name => 'sl1', :product_id => 1, :price_unit => 21, :product_uom => 1), SaleOrderLine.new(:name => 'sl2', :product_id => 1, :price_unit => 21, :product_uom => 1)] #create one order line
        so.save
        so.amount_total.should == 42.0
      end

      it "should be able to assign a polymorphic relation" do
        #TODO implement!
      end
    end

    describe "ARel emulation" do
      it "should have an 'all' method" do
        ResUsers.all be_kind_of(Array)
      end
    end

    describe "wizard management" do
      it "should be possible to pay an invoice in one step" do        
        inv = AccountInvoice.find(:last).copy() #creates a draft invoice        
        inv.state.should == "draft"
        inv.wkf_action('invoice_open')
        inv.state.should == "open"
        voucher = AccountVoucher.new({:amount=>inv.amount_total, :type=>"receipt", :partner_id => inv.partner_id.id}, {"default_amount"=>inv.amount_total, "invoice_id"=>inv.id})
        voucher.on_change("onchange_partner_id", [], :partner_id, inv.partner_id.id, AccountJournal.find('account.bank_journal').id, 0.0, 1, 'receipt', false)
        voucher.save
        voucher.wkf_action 'proforma_voucher'
        
        inv.reload
      end

      it "should be possible to call resource actions and workflow actions" do
        s = SaleOrder.find(1).copy()
        s.wkf_action('order_confirm')
        s.wkf_action('manual_invoice')
        i = s.invoice_ids[0]
        i.journal_id.update_posted = true
        i.journal_id.save
        i.wkf_action('invoice_open')
        i.wkf_action('invoice_cancel')
        i.action_cancel_draft
        s.reload.state.should == "invoice_except"
      end
    end

    describe "Delete resources" do
      it "should be able to call unlink" do
        ids = ProductProduct.search([['name', 'ilike', 'testProduct']])
        ProductProduct.unlink(ids)
      end

      it "should be able to destroy loaded business objects" do
        orders = SaleOrder.find(:all, :domain => [['origin', 'ilike', 'ooor_test']])
        orders.each {|order| order.destroy}

        invoices = AccountInvoice.find(:all, :domain => [['origin', 'ilike', 'ooor_test']])
        invoices.each {|inv| inv.destroy}
      end
    end

  end

  describe "Multi-instance and class name scoping" do
    before(:all) do
      @ooor1 = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database, :scope_prefix => 'OE1', :models => ['res.partner', 'product.product'], :reload => true)
      @ooor2 = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database, :scope_prefix => 'OE2', :models => ['res.partner', 'product.product'], :reload => true)
    end

    it "should still be possible to find a ressource using an absolute id" do
      OE1::ResPartner.find('res_partner_1').should be_kind_of(OE1::ResPartner)
    end

    it "should be able to read in one instance and write in an other" do
      p1 = OE1::ProductProduct.find(1)
      p2 = OE2::ProductProduct.create(:name => p1.name, :categ_id => p1.categ_id.id)
      p2.should be_kind_of(OE2::ProductProduct)
    end
  end

  describe "Multi-format serialization" do
    it "should serialize in json" do
      ProductProduct.find(1).as_json
    end
    it "should serialize in json" do
      ProductProduct.find(1).to_xml
    end
  end

  describe "Ruby OpenERP extensions" do
    before(:all) do
      @ooor = Ooor.new(:url => @url, :username => @username, :password => @password, :database => @database, :helper_paths => [File.dirname(__FILE__) + '/helpers/*'], :reload => true)
    end

    it "should have default core helpers loaded" do
      mod = IrModuleModule.find(:first, :domain=>['name', '=', 'sale'])
      mod.print_dependency_graph
    end

    it "should load custom helper paths" do
      IrModuleModule.say_hello.should == "Hello"
      mod = IrModuleModule.find(:first, :domain=>['name', '=', 'sale'])
      mod.say_name.should == "sale"
    end

  end

end
