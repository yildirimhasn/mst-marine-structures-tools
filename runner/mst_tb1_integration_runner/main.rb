# frozen_string_literal: true
require 'sketchup.rb'
require 'json'
require 'digest'
require 'time'
require 'tempfile'

# This runner never patches SketchUp classes or the MST API and never runs the
# original KN1 scenarios. Test records below are ordinary in-memory Ruby objects.
module MSTTB1Runner
  VERSION='1.2.7'.freeze
  EXPECTED_VERSION='0.51.5'.freeze
  EXPECTED_BUILD='v0.51.5 TB1 FIX1'.freeze
  class Failure < StandardError;end
  class Skip < StandardError;end
  class Record
    attr_reader :attributes
    def initialize(type,values={});@attributes={'element_type'=>type}.merge(values);end
    def get_attribute(_dict,key,default=nil);@attributes.fetch(key,default);end
    def persistent_id;0;end
    def set_attribute(*);raise Failure,'Saf hesap testi veri yazmaya çalıştı.';end
  end

  def self.api
    raise Skip,'MST yüklenmemiş; önce ana eklentinin yükleme hatasını inceleyin.' unless defined?(MAG::MarineStructuresTools)
    MAG::MarineStructuresTools
  end
  def self.assert(condition,message='Beklenen sonuç alınamadı.');raise Failure,message unless condition;end
  def self.near(actual,expected,tolerance=1e-7)
    assert(actual.is_a?(Numeric)&&actual.finite?&&(actual-expected).abs<=tolerance,"Beklenen #{expected}; alınan #{actual.inspect}")
  end
  def self.rejects
    rejected=false
    begin
      yield
    rescue Skip,NameError
      raise
    rescue StandardError
      rejected=true
    end
    assert(rejected,'Geçersiz girdi reddedilmedi.')
  end
  def self.check(report,name)
    started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
    row={name:name,status:'pass',detail:yield}
  rescue Skip=>error
    row={name:name,status:'skip',message:error.message}
  rescue StandardError,SyntaxError,LoadError=>error
    row={name:name,status:'fail',error_class:error.class.name,message:error.message,backtrace:Array(error.backtrace).first(8)}
  ensure
    row ||= {name:name,status:'fail',message:'Test tamamlanamadı.'}
    row[:elapsed_ms]=((Process.clock_gettime(Process::CLOCK_MONOTONIC)-started)*1000).round(1)
    report[:checks]<<row
    puts "[#{row[:status].upcase}] #{name}#{row[:message] ? ': '+row[:message] : ''}"
  end
  def self.root
    paths=$LOADED_FEATURES.select{|file|file.tr('\\','/').downcase.end_with?('/marine_structures_tools/main.rb')}
    return File.dirname(File.expand_path(paths.last)) unless paths.empty?
    plugins=Sketchup.find_support_file('Plugins')
    candidate=plugins && File.join(plugins,'marine_structures_tools')
    raise Skip,'Kurulu MST kaynak klasörü bulunamadı.' unless candidate&&File.file?(File.join(candidate,'main.rb'))
    candidate
  end
  def self.input
    {'axis'=>[[0,0,0],[10,0,0]],'step'=>3,'extra'=>[],
     'triangles'=>[[[-1,-20,-5],[11,-20,-5],[11,20,-5]],[[-1,-20,-5],[11,20,-5],[-1,20,-5]]],
     'types'=>{'T1'=>{'mode'=>'parametric','crest'=>0,'width'=>4,'slope_left'=>1,'slope_right'=>1,'layers'=>[{'code'=>'CORE-01','thickness'=>0}]}},
     'reaches'=>[{'from'=>0,'type'=>'T1'}]}
  end
  def self.core(report)
    check(report,'MST yüklenmiş mi?'){assert(defined?(MAG::MarineStructuresTools),'MST ad alanı yüklenmemiş.');true}
    check(report,'Yüklü sürüm ve yapı') do
      assert(api.const_defined?(:VERSION,false)&&api::VERSION==EXPECTED_VERSION,"Beklenen sürüm #{EXPECTED_VERSION}; yüklü #{api.const_defined?(:VERSION,false) ? api::VERSION : 'yok'}")
      assert(api.const_defined?(:MST_BUILD,false)&&api::MST_BUILD==EXPECTED_BUILD,'TB1 birleşim yapı adı uyuşmuyor; kurulumdan sonra SketchUp yeniden başlatıldı mı?')
      {version:api::VERSION,build:api::MST_BUILD}
    end
    check(report,'TB1 özellik işaretleri') do
      required=%w[TB1 DR5 PC2 KN1 BQ1 RB5 SP1]
      missing=required.reject{|key|api.const_defined?(:MST_FEATURES,false)&&api::MST_FEATURES.include?(key)}
      assert(missing.empty?,"Eksik özellikler: #{missing.join(', ')}");required
    end
    check(report,'Aktarılan araçların giriş noktaları') do
      names=%w[project_workspace_refresh controlled_editor_preview material_change_show elevation_sync_show model_health_show scoped_model_health_show batch_record_repair_show relationship_audit_show rf_special_qto rf_live_qto mst_element_rebar mst_pile_canonical_weight_kg]
      missing=names.reject{|name|api.respond_to?(name)}
      assert(missing.empty?,"Eksik metodlar: #{missing.join(', ')}");{methods:names.length}
    end
    check(report,'Kurulu dosyalar doğru birleşim paketine ait mi?') do
      manifest=JSON.parse(File.read(File.join(__dir__,'expected_sources.json'),encoding:'UTF-8'))
      parent=File.dirname(root);issues=[]
      manifest.fetch('files').each do |relative,expected|
        file=File.join(parent,relative)
        issues << "Eksik: #{relative}" unless File.file?(file)
        issues << "Farklı: #{relative}" if File.file?(file)&&Digest::SHA256.file(file).hexdigest!=expected
      end
      assert(issues.empty?,issues.join("\n"));{verified_files:manifest['files'].length}
    end
    check(report,'Ruby dosyalarının derlenmesi — kod çalıştırılmaz') do
      raise Skip,'RubyVM derleyicisi bu ortamda bulunmuyor.' unless defined?(RubyVM::InstructionSequence)
      files=Dir.glob(File.join(root,'**','*.rb'))+[File.join(File.dirname(root),'marine_structures_tools.rb')]
      issues=[]
      files.uniq.each do |file|
        begin;RubyVM::InstructionSequence.compile_file(file)
        rescue SyntaxError,StandardError=>error;issues << "#{file}: #{error.message}";end
      end
      assert(issues.empty?,issues.join("\n"));{compiled_files:files.uniq.length}
    end
    check(report,'Metraj motoru kaynak sürümü') do
      row=api::QuantityService.record(Record.new('unknown'),:count)
      assert(row[:engine_version]=='2-tb1',"Motor sürümü: #{row.inspect}");row
    end
    check(report,'Ruby 2.5 uyumu — kiriş değişiklik listesinin hazırlanması') do
      before={'length_m'=>2.0,'width_m'=>1.0,'concrete_class'=>'C30/37'}
      values={'length_m'=>3.0,'width_m'=>1.0,'concrete_class'=>'C35/45'}
      changes=api::HeadBeamEditor.change_list(before,values)
      assert(changes.length==2&&changes.none?(&:nil?),changes.inspect)
      assert(changes.map{|row|row[:after]}==[3.0,'C35/45'],changes.inspect)
      assert(api::HeadBeamEditor.change_list(before,before).empty?,'Değişmeyen değerler listeye eklendi.')
      {changes:changes,runtime_filter_map_available:[].respond_to?(:filter_map)}
    end
    check(report,'Ruby 2.5 uyumu — değişen geçmiş miktarını karşılaştırma') do
      quantity={value:3.0,state:'calculated',unit:'t',method:'canonical_pipe_mass',engine_version:'2-tb1'}
      before={schema:'mst.model-health/1',version:EXPECTED_VERSION,created_at:'test-before',records:[{key:'test-1',uid:'test-uid',id:'P-TEST',label:'Test',type:'steel_pipe_pile',state:'checked',checks:[],quantities:{steel_t:quantity}}]}
      after=Marshal.load(Marshal.dump(before));after[:created_at]='test-after'
      after[:records][0][:quantities][:steel_t][:value]=4.0
      frozen_before=Marshal.dump(before);frozen_after=Marshal.dump(after)
      result=api::HealthHistory.compare_reports(before,after)
      assert(result[:summary][:changed]==1,result.inspect)
      changes=result[:records][0][:quantities]
      assert(changes.length==1&&changes[0][:key]==:steel_t,changes.inspect)
      assert(before==Marshal.load(frozen_before)&&after==Marshal.load(frozen_after),'Bellekteki karşılaştırma girdileri değiştirildi.')
      {changed:result[:summary][:changed],quantities:changes}
    end
    check(report,'Ruby 2.5 uyumu — aynı geçmiş raporunda sahte değişiklik yok') do
      record={key:'test-1',uid:'test-uid',id:'P-TEST',label:'Test',type:'steel_pipe_pile',state:'checked',checks:[],quantities:{steel_t:{value:3.0,state:'calculated',unit:'t',method:'canonical_pipe_mass',engine_version:'2-tb1'}}}
      data={schema:'mst.model-health/1',version:EXPECTED_VERSION,records:[record]}
      result=api::HealthHistory.compare_reports(data,Marshal.load(Marshal.dump(data)))
      assert(result[:records].empty?,result.inspect);true
    end
    check(report,'Ondalık virgül okunması'){near(api::QuantityService.number('1,25','test'),1.25);true}
    check(report,'Negatif, bozuk ve sonsuz miktar reddi') do
      [-1,'bozuk','NaN',Float::INFINITY].each{|raw|rejects{api::QuantityService.number(raw,'test')}};true
    end
    check(report,'Kazık çeliği eski ağırlık önbelleğinden bağımsız mı?') do
      entity=Record.new('steel_pipe_pile',{'diameter_mm'=>'1000,0','thickness_mm'=>10,'length_m'=>20,'weight_kg'=>1})
      before=Marshal.dump(entity.attributes)
      row=api::QuantityService.record(entity,:steel_t)
      expected=Math::PI/4*(1.0**2-0.98**2)*20*7850/1000
      near(row[:value],expected);assert(row[:method]=='canonical_pipe_mass');assert(before==Marshal.dump(entity.attributes),'Test kaydı değişti.');row
    end
    check(report,'Kazıkta gerçek boy önceliği') do
      entity=Record.new('steel_pipe_pile',{'diameter_mm'=>1000,'thickness_mm'=>10,'length_m'=>20,'actual_length_m'=>10})
      near(api::QuantityService.value(entity,:steel_t),Math::PI/4*(1.0**2-0.98**2)*10*7850/1000);true
    end
    check(report,'Geçersiz kazık kesiti sıfır gibi raporlanmıyor mu?') do
      row=api::QuantityService.record(Record.new('steel_pipe_pile',{'diameter_mm'=>20,'thickness_mm'=>10,'length_m'=>2}),:steel_t)
      assert(row[:state]=='invalid'&&row[:value].nil?,row.inspect);true
    end
    %w[bim_detail drawing_detail auto_detail].each do |mode|
      check(report,"Donatı kaynağı — #{mode}") do
        row=api::QuantityService.record(Record.new('deck_slab',{'rebar_mode'=>mode,'rebar_t'=>'1,25'}),:rebar_t)
        near(row[:value],1.25);assert(row[:method]=='bim:rebar_t',row.inspect);row
      end
    end
    check(report,'Eksik BIM donatısı tahmine çevrilmiyor mu?') do
      row=api::QuantityService.record(Record.new('deck_slab',{'rebar_mode'=>'drawing_detail'}),:rebar_t)
      assert(row[:state]=='missing',row.inspect);true
    end
    check(report,'Bozuk BIM donatısı sıfıra çevrilmiyor mu?') do
      row=api::QuantityService.record(Record.new('deck_slab',{'rebar_mode'=>'auto_detail','rebar_t'=>'bad'}),:rebar_t)
      assert(row[:state]=='invalid'&&row[:value].nil?,row.inspect);true
    end
    check(report,'Kazık BIM kafesi kg → ton') do
      row=api::QuantityService.record(Record.new('steel_pipe_pile',{'pile_rebar_mode'=>'bim_detail','pile_rebar_json'=>'{}','pile_cage_rebar_kg'=>600}),:rebar_t)
      near(row[:value],0.6);assert(row[:method]=='bim:pile_cage_rebar_kg',row.inspect);row
    end
    check(report,'Dolgu kaynak sağlayıcılarının dördü mevcut mu?') do
      %w[alt1 alt2 geometry special].map{|mode|assert(api::RockfillSources.provider(mode).respond_to?(:quantities),mode);mode}
    end
    check(report,'Bilinmeyen dolgu kaynağı reddi'){rejects{api::RockfillSources.provider('invalid')};true}
    check(report,'Aks sıralaması ve ters yinelenen kenar') do
      points=api::AxisChain.order([[[1,0,0],[2,0,0]],[[1,0,0],[0,0,0]],[[2,0,0],[1,0,0]]])
      assert(points==[[0.0,0.0,0.0],[1.0,0.0,0.0],[2.0,0.0,0.0]],points.inspect);points
    end
    check(report,'Dallanan aks reddi') do
      rejects{api::AxisChain.order([[[0,0,0],[1,0,0]],[[1,0,0],[2,0,0]],[[1,0,0],[1,1,0]]])};true
    end
    check(report,'Dolgu analitik örnek — 45 m² × 10 m = 450 m³') do
      result=api::RockfillGeometry.calculate(input)
      near(result.fetch('total'),450);near(result.fetch('total_length'),10)
      {volume_m3:result['total'],length_m:result['total_length']}
    end
    check(report,'Dolgu tip geçişi — 500 m³') do
      data=input;data['types']['T2']=Marshal.load(Marshal.dump(data['types']['T1']))
      data['types']['T2']['width']=6;data['reaches']<<{'from'=>5,'type'=>'T2'}
      near(api::RockfillGeometry.calculate(data).fetch('total'),500);true
    end
    check(report,'Üst üste binen farklı dolgu malzemeleri reddi') do
      loop_points=[[0,-5],[4,-5],[4,0],[0,0]]
      parts=[{'code'=>'A','loops'=>[loop_points]},{'code'=>'B','loops'=>[loop_points]}]
      rejects{api::RockfillGeometry.section(parts,[[[-1,-5],[5,-5]]])};true
    end
    check(report,'TIN üçgenleme — birim kare alanı') do
      triangles=api::RockfillTIN.triangulate([[[0,0,0],[1,0,0]],[[1,0,0],[1,1,0]],[[1,1,0],[0,1,0]],[[0,1,0],[0,0,0]]])
      near(triangles.sum{|a,b,c|((b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])).abs/2.0},1);{triangles:triangles.length}
    end
    check(report,'Onaylı dolgu referansı hesaplanıyor mu?') do
      data=JSON.parse(File.read(File.join(root,'data','akdeniz_reference_sections.json'),encoding:'UTF-8'))
      result=api.rf02_reference_calculate(data)
      assert(result['complete_scope']==true,'Referans kapsamı tamamlanmadı.')
      assert(result.fetch('totals_m3').values.all?{|n|n.is_a?(Numeric)&&n.finite?&&n>=0},'Geçersiz referans hacmi.')
      {fingerprint:data['reference_fingerprint'],totals_m3:result['totals_m3']}
    end
    check(report,'Değiştirilmiş onaylı referans reddi') do
      data=JSON.parse(File.read(File.join(root,'data','akdeniz_reference_sections.json'),encoding:'UTF-8'))
      data['assumptions']<<'RUNNER: değiştirilmiş kopya'
      rejects{api.rf02_reference_calculate(data)};true
    end
  end

  def self.dictionary(entity,name)
    dict=entity.attribute_dictionary(name,false);values={}
    dict.each_pair{|key,value|values[key]=value} if dict
    JSON.generate(values.sort_by{|key,_|key})
  end
  def self.model_read(report)
    check(report,'Aktif modelde miktar okuma — en fazla 100 desteklenen eleman') do
      model=Sketchup.active_model
      before={selection:model.selection.to_a.map(&:persistent_id),path:Array(model.active_path).map(&:persistent_id),modified:model.modified?,attributes:dictionary(model,api::DICT)}
      entries=api::ProjectWorkspace.entries(model);sample=entries.first(100)
      snapshots=sample.map{|entry|[entry[:entity],dictionary(entry[:entity],api::DICT)]}
      begin
        observations=sample.map do |entry|
          entity=entry[:entity]
          quantities=%i[concrete_m3 steel_t rebar_t formwork_m2].each_with_object({}) do |key,out|
            out[key]=api::ProjectWorkspace.quantity(entity,key)
          end
          {pid:entity.persistent_id,type:entity.get_attribute(api::DICT,'element_type',''),quantities:quantities}
        end
        report[:model_observations]={root_entities:model.entities.length,editing_context_depth:Array(model.active_path).length,supported_elements:entries.length,read_elements:sample.length,remaining_elements:entries.length-sample.length,records:observations}
        invalid=observations.sum{|row|row[:quantities].values.count{|quantity|%w[missing invalid].include?(quantity[:state])}}
        report[:checks]<<{name:'Model verisi: eksik/geçersiz miktarlar',status:'warn',message:"#{invalid} miktar kaydı eksik veya geçersiz. Ayrıntı model_observations bölümünde; bu bir test motoru hatası olduğunu tek başına göstermez."} if invalid>0
        raise Skip,'Modelde desteklenen eleman bulunmadı.' if sample.empty?
        {read_elements:sample.length,missing_or_invalid_quantities:invalid}
      ensure
        after={selection:model.selection.to_a.map(&:persistent_id),path:Array(model.active_path).map(&:persistent_id),modified:model.modified?,attributes:dictionary(model,api::DICT)}
        assert(before==after,'Okuma sırasında model bağlamı/kaydı değişti.')
        assert(snapshots.all?{|entity,attrs|dictionary(entity,api::DICT)==attrs},'Okuma sırasında eleman kaydı değişti.')
      end
    end
  end
  def self.text(report)
    lines=["MST TB1 BİRLEŞİM TESTİ — #{VERSION} (beklenen MST #{EXPECTED_BUILD})","UTC: #{report[:time_utc]}","SketchUp: #{report[:sketchup]} | Ruby: #{report[:ruby]}","Mod: #{report[:mode]}","Sonuç: #{report[:summary].map{|key,value|"#{key}=#{value}"}.join(' | ')}",'']
    report[:checks].each do |row|
      lines << "[#{row[:status].upcase}] #{row[:name]}"
      lines << row[:message].to_s if row[:message]
      lines << JSON.generate(row[:detail]) if row[:detail]
      Array(row[:backtrace]).each{|line|lines << "  #{line}"}
    end
    lines << '' << 'Bu rapor yükleme/saf hesap testidir; gerçek geometri üretimi, düzenleme, Undo ve mühendislik kabul testinin yerine geçmez.'
    lines << 'Model okuma ayrıntıları JSON raporunda bulunur.' if report[:model_observations]
    lines.join("\n")+"\n"
  end
  def self.run(with_model=false)
    owned=false
    return UI.messagebox('Test zaten çalışıyor.') if @running
    owned=true;@running=true
    report={schema:'mst.tb1.integration-runner/1',runner_version:VERSION,time_utc:Time.now.utc.iso8601,sketchup:Sketchup.version,ruby:RUBY_VERSION,mode:with_model ? 'core_and_model_read' : 'core_only',checks:[]}
    core(report);model_read(report) if with_model
    report[:summary]=%w[pass fail warn skip].each_with_object({}){|state,out|out[state]=report[:checks].count{|row|row[:status]==state}}
    @report=report
    puts text(report)
    summary=report[:summary]
    UI.messagebox("MST Birleşim Testi\nGeçti: #{summary['pass']}\nHata: #{summary['fail']}\nUyarı: #{summary['warn']}\nAtlandı: #{summary['skip']}\n\nSonuçları Ruby Console'dan kopyalayabilir veya aynı menüden TXT + JSON olarak kaydedebilirsin.")
    report
  rescue StandardError,SyntaxError,LoadError=>error
    report ||= {schema:'mst.tb1.integration-runner/1',checks:[]}
    report[:checks]<<{name:'Test çalıştırıcısı',status:'fail',message:error.message,error_class:error.class.name,backtrace:Array(error.backtrace).first(8)}
    report[:summary]=%w[pass fail warn skip].each_with_object({}){|state,out|out[state]=report[:checks].count{|row|row[:status]==state}}
    @report=report
    puts JSON.pretty_generate(report)
    UI.messagebox("Test aracı hata verdi: #{error.message}\nKısmi rapor menüden kaydedilebilir.")
    report
  ensure
    @running=false if owned
  end
  def self.write(path,content)
    file=Tempfile.new(['mst_test_', '.tmp'],File.dirname(path));file.binmode
    begin;file.write(content.encode('UTF-8'));file.flush;file.fsync;file.close;File.rename(file.path,path)
    ensure;file.close!;end
  end
  def self.save
    return UI.messagebox('Önce birleşim testini çalıştır.') unless @report
    path=UI.savepanel('MST test raporu — JSON ve TXT kaydet','','MST_TB1_Test_'+Time.now.strftime('%Y%m%d_%H%M%S')+'.json')
    return unless path
    base=path.sub(/\.(json|txt)\z/i,'')
    targets=[base+'.json',base+'.txt']
    if targets.any?{|target|File.exist?(target)}
      return unless UI.messagebox('Bu ada ait rapor var. JSON ve TXT dosyaları değiştirilsin mi?',MB_YESNO)==IDYES
    end
    written=[]
    write(targets[0],JSON.pretty_generate(@report));written<<targets[0]
    write(targets[1],text(@report));written<<targets[1]
    UI.messagebox("Rapor kaydedildi:\n#{written.join("\n")}\n\nBu dosyaları sohbetten paylaşabilirsin.")
  rescue StandardError=>error
    UI.messagebox("Rapor kaydedilemedi: #{error.message}\n#{Array(written).empty? ? 'Dosya kaydedilmedi.' : 'Kaydedilen: '+written.join(', ')}\nSonuçlar Ruby Console içinde de bulunur.")
  end
end

unless file_loaded?(__FILE__)
  menu=UI.menu('Extensions').add_submenu('MST 0.51.5 | Birleşim Testi — Salt Okunur')
  menu.add_item('1 — Birleşim ve Saf Hesap Testlerini Çalıştır'){MSTTB1Runner.run(false)}
  menu.add_item('2 — Aynı Testler + Aktif Modelden Miktar Oku'){MSTTB1Runner.run(true)}
  menu.add_item('3 — Son Raporu TXT + JSON Kaydet'){MSTTB1Runner.save}
  file_loaded(__FILE__)
end
