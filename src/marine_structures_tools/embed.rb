# frozen_string_literal: true
# v0.38 UI2 — Tek pencere: eskiden ayrı HtmlDialog açan bütün araçlar ana pencerenin
# içinde bir sayfa olarak açılır. MSTEmbedDialog, HtmlDialog'un kullanılan API'sini taklit
# eder; böylece araçların kendi kodu (callback'ler, execute_script, close) değişmeden çalışır.
require 'json'
module MAG
module MarineStructuresTools
class MSTEmbedDialog
  attr_reader :key,:title,:html
  def initialize(owner,key,title)
    @owner=owner;@key=key.to_s;@title=title.to_s;@cbs={};@visible=false;@html='';@host=nil;@on_closed=nil
  end
  def set_file(path);@html=File.read(path,encoding:'UTF-8');true;end
  def set_html(h);@html=h.to_s;true;end
  def set_url(u);@html="<!doctype html><html><head><meta http-equiv='refresh' content='0;url=#{u}'></head><body></body></html>";true;end
  def add_action_callback(name,&b)
    @cbs[name.to_s]=b
    @owner.mst_embed_forward(name.to_s) rescue nil
    true
  end
  def callbacks;@cbs.keys;end
  def call_back(name,args)
    cb=@cbs[name.to_s]
    return false unless cb
    cb.call(self,*args)
    true
  end
  def show
    @host=@owner.mst_main_dialog
    @visible=true
    @owner.mst_host_exec("mstEmbedShow(#{JSON.generate(@key)},#{JSON.generate(@title)},#{JSON.generate(@html)})")
    true
  end
  def show_modal;show;end
  def execute_script(js)
    return false unless visible?
    @owner.mst_host_exec("mstEmbedExec(#{JSON.generate(@key)},#{JSON.generate(js.to_s)})")
    true
  end
  def visible?
    h=@owner.mst_main_dialog
    @visible && !h.nil? && h.equal?(@host) && h.visible?
  end
  def bring_to_front
    return false unless visible?
    @owner.mst_host_exec("mstEmbedFocus(#{JSON.generate(@key)})")
    @host.bring_to_front rescue nil
    true
  end
  def close
    was=visible?
    @visible=false
    @owner.mst_host_exec("mstEmbedClose(#{JSON.generate(@key)})") if was
    @on_closed.call if @on_closed && was
    true
  end
  def closed_by_user!
    @visible=false
    @on_closed.call if @on_closed
  end
  def set_on_closed(&b);@on_closed=b;true;end
  def set_can_close(&b);true;end
  def set_size(*_a);true;end
  def set_position(*_a);true;end
  def center;true;end
  def min_width=(_v);end
  def min_height=(_v);end
  def get_size;[0,0];end
end

def mst_main_dialog;@d;end
def mst_embed_registry;@mst_embeds||={};end

# Ana pencere yüklenmeden gelen komutlar sıraya alınır (ilk açılışta araç doğrudan çağrılırsa).
def mst_host_exec(js)
  return false unless @d
  if @mst_host_ready
    @d.execute_script(js)
  else
    (@mst_host_queue||=[]) << js
  end
  true
end

def mst_host_ready!
  @mst_host_ready=true
  q=@mst_host_queue||[];@mst_host_queue=[]
  q.each{|js|@d.execute_script(js)}
end

def mst_host_reset!
  @mst_host_ready=false;@mst_host_queue=[]
end

# UI::HtmlDialog.new yerine: ana pencerede gömülü sayfa. MST_EMBED_OFF modeli özniteliği
# '1' ise (acil durum) eski ayrı pencere davranışı.
def mst_html_dialog(key,opts={})
  if (Sketchup.active_model.get_attribute(DICT,'mst_embed_off','0').to_s=='1' rescue false)
    return UI::HtmlDialog.new(opts)
  end
  show_dialog unless @d && @d.visible?
  title=(opts[:dialog_title] || opts['dialog_title']).to_s.sub(/\AMarine Structures\s*-\s*/,'')
  mst_embed_registry[key.to_s]=MSTEmbedDialog.new(self,key,title)
end

def mst_embed_dispatch(key,name,json)
  dl=mst_embed_registry[key.to_s]
  return false unless dl
  args=(JSON.parse(json.to_s) rescue [])
  args=[args] unless args.is_a?(Array)
  if name.to_s=='__closed'
    dl.closed_by_user!
    return true
  end
  ok=dl.call_back(name,args)
  puts "MST gömülü sayfa: #{key}.#{name} için callback yok." unless ok
  ok
rescue => e
  UI.messagebox("#{dl ? dl.title : key}: #{e.message}")
  false
end

# Güvenlik ağı: SketchUp gömülü sayfaya kendi `sketchup` nesnesini de verirse çağrılar ana
# pencereye gelir. Aracın callback adlarını ana pencereye de (ana pencerenin kendi adlarıyla
# çakışmadan) bağlarız; böylece iki yol da aynı Ruby bloğuna ulaşır.
def mst_embed_forward(name)
  d=@d
  return false unless d && d.respond_to?(:add_action_callback)
  if !@mst_fwd_host.equal?(d)
    @mst_fwd_host=d;@mst_fwd=[]
  end
  return false if @mst_fwd.include?(name) || (@mst_main_cbs||[]).include?(name)
  @mst_fwd << name
  @mst_recording_off=true
  begin
    d.add_action_callback(name){|_,*a|mst_embed_forward_call(name,a)}
  ensure
    @mst_recording_off=false
  end
  true
end

def mst_embed_forward_call(name,args)
  dl=mst_embed_registry.values.reverse.find{|x|x.visible? && x.callbacks.include?(name)} ||
     mst_embed_registry.values.reverse.find{|x|x.callbacks.include?(name)}
  return false unless dl
  dl.call_back(name,args)
rescue => e
  UI.messagebox("#{dl ? dl.title : name}: #{e.message}")
  false
end

def mst_register_embed_callbacks(d)
  owner=self
  @mst_main_cbs=[]
  d.define_singleton_method(:add_action_callback) do |n,&b|
    owner.instance_variable_get(:@mst_main_cbs) << n.to_s unless owner.instance_variable_get(:@mst_recording_off)
    super(n,&b)
  end
  d.add_action_callback('mst_embed'){|_,key,name,json|mst_embed_dispatch(key,name,json)}
  d.add_action_callback('mst_embed_ready'){|_|mst_host_ready!}
end
end
end
