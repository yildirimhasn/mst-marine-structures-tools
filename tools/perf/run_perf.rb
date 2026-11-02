# Metraj okuyuculari performans olcumu (SketchUp DISINDA, sahte nesne; sureler SketchUp suresi DEGILDIR — oran ve cagri
# sayisi kanittir). Eklenti tools/golden/sketchup_stub.rb altinda gercek yukleme sirasiyla yuklenir, tools/perf/scale_fixture.rb
# modeli kurulur. src/ DEGISTIRILMEZ; kaynaklar `git archive` ile gecici klasore acilir.
#
# Kullanim (depo kokunden):
#   ruby tools/perf/run_perf.rb all [taban=872d3a3] [yeni=c8f9d70] [bloklar=8,15,30] [tekrar=3]
#       → her kaynak × her n × her islem AYRI SURECTE; medyan tablosu + buyume orani; ardindan profil (n'e gore cagri sayilari)
#   ruby tools/perf/run_perf.rb time <marine_structures_tools> <blok> <islem> <tekrar>   (alt surec; JSON satiri basar)
#   ruby tools/perf/run_perf.rb prof <marine_structures_tools> <blok> <islem> [ilk=25]    (alt surec; JSON satiri basar)
#   ruby tools/perf/run_perf.rb obs  <marine_structures_tools> <blok> <islem>              (alt surec; SketchUp islem disi yazim benzetimi:
#       acik islem yokken her set_attribute = ortuk islem → DependencyModelObserver#onTransactionCommit; UI.start_timer
#       bloklari islem sonunda calistirilir. VARSAYIM: SketchUp 2020'de islem disi yazim kendi islemini/Geri Al girdisini acar —
#       SketchUp icinde dogrulanmadi)
# Islemler: boq_rows qto3_snapshot boq_quantities send_boq qto_summary mst_workflow_status
#   (P1 ek, yalniz time/prof/obs ile): progress_send prog2_view boq2_payload mst_send_rebar_page project_workspace_refresh model_audit
require 'json'
require 'tmpdir'
require 'open3'
require 'stringio'

OPS = %w[boq_rows qto3_snapshot boq_quantities send_boq qto_summary mst_workflow_status].freeze
WATCH = %w[collect_elements mst_collect_elements_raw dependency_graph mst_collect_toppings boq_trace_entities boq_trace_entities_base
           mst_bk_pile_embed mst_hb_zone_segments mst_boq_info_rows mst_audit_v0515 topping_quantities mst_qto_detail_rows
           boq_quantities boq_rows boq_rows_base qto3_snapshot].freeze

def clock; Process.clock_gettime(Process::CLOCK_MONOTONIC); end

def load_plugin(dir)
  require_relative '../golden/sketchup_stub'
  $model = Sketchup::Model.new
  $stderr_buf = StringIO.new
  require File.expand_path(File.join(dir, 'main.rb'))
  require_relative 'scale_fixture'
  MAG::MarineStructuresTools
end

class PerfDialog
  attr_reader :js
  def initialize; @js = []; end
  def execute_script(j); @js << j.bytesize; (@heads ||= []) << j[0, 40]; (@full ||= []) << j; true; end
  def heads; @heads || []; end
  def full; @full || []; end
  def visible?; true; end
  def method_missing(*_a); nil; end
  def respond_to_missing?(*) true end
end

def run_op(m, op)
  case op
  when 'boq_rows' then m.boq_rows(true)
  when 'qto3_snapshot' then m.qto3_snapshot
  when 'boq_quantities' then m.boq_quantities
  when 'send_boq' then d = PerfDialog.new; m.send_boq(d); raise 'send_boq: setBOQ yok' if d.js.empty?
  when 'qto_summary' then d = PerfDialog.new; m.qto_summary(d); raise 'qto_summary: setQTO yok' if d.js.empty?
  when 'mst_workflow_status' then m.mst_workflow_status
  when 'progress_send' then d = PerfDialog.new; m.progress_send(d); h = d.heads.join('|'); raise "progress_send: #{h}" unless h.include?('progressLoaded')
  when 'prog2_view' then d = PerfDialog.new; m.boq2_set_view('{"date":""}'); m.progress_send(d); h = d.heads.join('|'); raise "prog2_view: #{h}" unless h.include?('progressLoaded')
  when 'boq2_payload' then m.boq2_payload
  when 'mst_send_rebar_page' then d = PerfDialog.new; m.mst_send_rebar_page(d); raise 'rebar: yok' if d.js.empty?
  when 'project_workspace_refresh' then m.instance_variable_set(:@d, PerfDialog.new); m.project_workspace_refresh
  when 'model_audit' then m.instance_variable_set(:@d, PerfDialog.new); m.model_audit
  else abort "bilinmeyen islem #{op}"
  end
end

# Profil: modulun (extend self) tum yontemleri singleton sinifa prepend edilen sarmalayici ile sarilir.
# Cagri sayisi her cagrida; kapsayici sure yalniz en distaki (ozyinelemesiz) cagrida eklenir.
def prof_wrap(mod, label, stats)
  pub = mod.instance_methods(false)
  priv = mod.private_instance_methods(false)
  w = Module.new
  (pub + priv).uniq.each do |nm|
    next if nm.to_s.start_with?('__') || %i[method_missing respond_to_missing? respond_to? initialize].include?(nm)
    key = "#{label}#{nm}"
    w.send(:define_method, nm) do |*a, &b|
      s = (stats[key] ||= [0, 0.0, 0, 0])
      s[0] += 1
      if s[2].zero?
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        g0 = $api_ga
        s[2] += 1
        begin
          super(*a, &b)
        ensure
          s[2] -= 1
          s[1] += Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
          s[3] += $api_ga - g0
        end
      else
        s[2] += 1
        begin
          super(*a, &b)
        ensure
          s[2] -= 1
        end
      end
    end
    w.send(:ruby2_keywords, nm)
    w.send(:private, nm) if priv.include?(nm) && !pub.include?(nm)
  end
  mod.singleton_class.prepend(w)
end

# SketchUp API cagri sayaci: Entity#get_attribute (ham geometri dahil her oge ziyaretinin vekili)
$api_ga = 0
module PerfApiCount
  def get_attribute(*a)
    $api_ga += 1
    super
  end
end

# Diger SketchUp API cagrilari (adet): gercek SketchUp'ta maliyeti sahteden cok farkli olabilecekler
$api_calls = Hash.new(0)
API_WATCH = {
  'Sketchup::Model' => %i[find_entity_by_persistent_id definitions entities active_entities],
  'Sketchup::Entity' => %i[attribute_dictionary attribute_dictionaries set_attribute parent persistent_id valid? transformation],
  'Sketchup::Drawingelement' => %i[bounds],
  'Sketchup::Group' => %i[entities definition volume],
  'Sketchup::ComponentInstance' => %i[definition],
  'Sketchup::ComponentDefinition' => %i[instances count_instances entities],
  'Sketchup::Face' => %i[area normal vertices edges loops]
}.freeze
def perf_api_install
  API_WATCH.each do |cls, names|
    k = Object.const_get(cls)
    w = Module.new
    names.each do |nm|
      next unless k.method_defined?(nm)
      key = "#{cls.split('::').last}##{nm}"
      w.send(:define_method, nm) do |*a, &b|
        $api_calls[key] += 1
        super(*a, &b)
      end
      w.send(:ruby2_keywords, nm)
    end
    k.prepend(w)
  end
end

def child(mode, dir, blocks, op, extra)
  m = load_plugin(dir)
  Sketchup::Entity.prepend(PerfApiCount)
  perf_api_install
  perf_build_fixture(blocks)
  all = []; m.collect_elements($model.entities, all)
  n = all.size
  olderr = $stderr
  $stderr = StringIO.new   # uyari satirlari (warn) olcumu kirletmesin; sayisi raporlanir
  out = { 'dir' => dir, 'blocks' => blocks, 'n' => n, 'op' => op }
  begin
    if mode == 'time'
      times = []
      gas = []
      calls1 = nil
      extra.to_i.times do
        $api_calls.clear
        w0 = ($writes ||= []).size
        g0 = $api_ga; t0 = clock; run_op(m, op); times << clock - t0; gas << $api_ga - g0
        out['writes'] ||= $writes[w0..].map { |pid, d, k| "#{pid == 1 ? 'model' : 'oge'}:#{d}:#{k.to_s.sub(/__.*/, '__*')}" }.tally
        calls1 ||= $api_calls.dup
      end
      out['get_attribute'] = gas
      out['api_calls'] = calls1
      out['times'] = times
      out['median'] = times.sort[times.size / 2]
    elsif mode == 'obs'
      out.merge!(obs_run(m, op))
    else
      stats = {}
      prof_wrap(m, '', stats)
      m.constants.map { |c| m.const_get(c) rescue nil }.each do |k|
        next unless k.is_a?(Module) && !k.is_a?(Class) && k.singleton_class.include?(k) && k != m
        prof_wrap(k, "#{k.name.split('::').last}.", stats)
      end
      $api_ga = 0
      t0 = clock; run_op(m, op); out['total'] = clock - t0
      top = (extra || 25).to_i
      out['api_total'] = $api_ga
      out['top'] = stats.sort_by { |_, v| -v[1] }.first(top).map { |k, v| [k, v[0], v[1].round(4), v[3]] }
      out['top_api'] = stats.sort_by { |_, v| -v[3] }.first(top).map { |k, v| [k, v[0], v[1].round(4), v[3]] }
      out['api'] = stats.transform_values { |v| v[3] }
      out['watch'] = WATCH.map { |w| [w, (stats[w] || [0])[0], (stats[w] || [0, 0.0])[1].round(4)] }
      out['calls'] = stats.transform_values { |v| v[0] }
    end
  rescue StandardError => e
    out['error'] = "#{e.class}: #{e.message[0, 200]} @ #{e.backtrace&.first}"
  ensure
    out['warn_lines'] = $stderr.string.lines.size
    out['warn_sample'] = $stderr.string.lines.first(3)
    $stderr = olderr
  end
  puts "PERFJSON #{JSON.generate(out)}"
end

# Islem disi yazim benzetimi (bkz. ust aciklama). Sayilan: ortuk islem, onTransactionCommit, zamanlayici ile calisan
# dependency_changes / dependency_graph / collect_elements cagrisi, bu calismanin get_attribute sayisi, suresi ve yazimi.
def obs_run(m, op)
  $op_depth = 0; $implicit = 0; $timers = {}; $timer_seq = 0
  Sketchup::Model.prepend(Module.new do
    def start_operation(*a); $op_depth += 1; super; end
    def commit_operation(*a); $op_depth -= 1 if $op_depth > 0; super; end
    def abort_operation(*a); $op_depth -= 1 if $op_depth > 0; super; end
  end)
  ui = UI.singleton_class
  ui.send(:define_method, :start_timer) { |*_a, &b| $timer_seq += 1; $timers[$timer_seq] = b; $timer_seq }
  ui.send(:define_method, :stop_timer) { |id| $timers.delete(id); true }
  obs = m::DependencyModelObserver.new
  Sketchup::Entity.prepend(Module.new do
    define_method(:set_attribute) do |*a|
      r = super(*a)
      if $op_depth.zero? && !$in_obs_timer
        $implicit += 1
        obs.onTransactionCommit($model)
      end
      r
    end
  end)
  cnt = Hash.new(0)
  %i[dependency_changes dependency_graph collect_elements].each do |nm|
    orig = m.method(nm)
    m.define_singleton_method(nm) { |*a, &b| cnt[nm] += 1; orig.call(*a, &b) }
  end
  w0 = ($writes ||= []).size
  t0 = clock; run_op(m, op); t_op = clock - t0
  wr_op = $writes[w0..].map { |pid, d, k| "#{pid == 1 ? 'model' : 'oge'}:#{d}:#{k.to_s.sub(/__.*/, '__*')}" }.tally
  op_cnt = cnt.dup; cnt.clear
  w1 = $writes.size; ops1 = $model.ops.size
  g0 = $api_ga; t1 = clock
  $in_obs_timer = true
  ran = 0
  until $timers.empty?
    id, b = $timers.first; $timers.delete(id); b.call; ran += 1
  end
  $in_obs_timer = false
  { 'op_s' => t_op, 'op_writes' => wr_op, 'op_calls' => op_cnt, 'implicit_tx' => $implicit, 'timers_run' => ran,
    'timer_s' => clock - t1, 'timer_get_attribute' => $api_ga - g0, 'timer_calls' => cnt.dup,
    'timer_writes' => $writes.size - w1, 'timer_ops' => $model.ops[ops1..] }
end

def spawn_child(*args)
  o, e, st = Open3.capture3('ruby', __FILE__, *args.map(&:to_s))
  line = o.lines.find { |l| l.start_with?('PERFJSON ') }
  abort "alt surec basarisiz (cikis #{st.exitstatus}): #{args.join(' ')}\n#{o[-800..] || o}\n#{e[-800..] || e}" unless line
  JSON.parse(line.sub('PERFJSON ', ''))
end

def driver(base, newc, blocks, reps)
  root = File.expand_path('../..', __dir__)
  Dir.mktmpdir('mst_perf') do |tmp|
    srcs = {}
    [base, newc].each do |c|
      d = File.join(tmp, c)
      Dir.mkdir(d)
      tar = File.join(tmp, "#{c}.tar")
      Dir.chdir(root) { system('git', 'archive', '-o', tar, c, 'src') or abort "git archive #{c} basarisiz" }
      Dir.chdir(d) { system('tar', '-xf', File.join('..', "#{c}.tar")) or abort 'tar acma basarisiz' }
      srcs[c] = File.join(d, 'src', 'marine_structures_tools')
    end
    res = {}
    OPS.each do |op|
      blocks.each do |b|
        srcs.each do |c, d|
          r = spawn_child('time', d, b, op, reps)
          res[[op, b, c]] = r
          warn "#{op} b=#{b} #{c}: n=#{r['n']} #{r['error'] || r['times'].map { |t| t.round(3) }.inspect} uyari=#{r['warn_lines']}"
        end
      end
    end
    puts "\n== SURE (sahte nesne, s; #{reps} tekrar medyani; her hucre ayri surec) =="
    puts format('%-20s %5s | %9s %9s %7s', 'islem', 'n', base, newc, 'yeni/eski')
    OPS.each do |op|
      blocks.each do |b|
        o = res[[op, b, base]]; n = res[[op, b, newc]]
        om = o['median']; nm = n['median']
        puts format('%-20s %5d | %9s %9s %7s', op, n['n'], om ? format('%.4f', om) : 'HATA', nm ? format('%.4f', nm) : 'HATA',
                    om && nm ? format('%.2f', nm / om) : '-')
        puts "   HATA #{base}: #{o['error']}" if o['error']
        puts "   HATA #{newc}: #{n['error']}" if n['error']
        puts "   tekrarlar #{base}=#{o['times']&.map { |t| t.round(4) }} #{newc}=#{n['times']&.map { |t| t.round(4) }} uyari=#{o['warn_lines']}/#{n['warn_lines']}"
        puts "   get_attribute cagrisi (tekrar basina) #{base}=#{o['get_attribute'].inspect} #{newc}=#{n['get_attribute'].inspect}"
        ac = (o['api_calls'] || {}).keys | (n['api_calls'] || {}).keys
        puts '   API (1. tekrar) ' + ac.sort.map { |k| "#{k}=#{(o['api_calls'] || {})[k].to_i}->#{(n['api_calls'] || {})[k].to_i}" }.join(' ')
      end
    end
    puts "\n== BUYUME (n en buyuk / n en kucuk sure orani; n orani #{format('%.1f', res[[OPS[0], blocks.last, base]]['n'].to_f / res[[OPS[0], blocks.first, base]]['n'])}) =="
    OPS.each do |op|
      [base, newc].each do |c|
        a = res[[op, blocks.first, c]]['median']; z = res[[op, blocks.last, c]]['median']
        puts format('%-20s %-8s %s', op, c, a && z ? format('%.1f', z / a) : '-')
      end
    end
    %w[qto3_snapshot boq_rows].each do |op|
      profs = {}
      blocks.each { |b| srcs.each { |c, d| profs[[b, c]] = spawn_child('prof', d, b, op, 25) } }
      srcs.each_key do |c|
        p = profs[[blocks.last, c]]
        puts "\n== PROFIL #{op} @ #{c}, n=#{p['n']} (sarmalayicili toplam #{p['total']&.round(3)} s) — ilk 25, kapsayici sure =="
        puts "   HATA: #{p['error']}" if p['error']
        puts "   (sutunlar: yontem, cagri, kapsayici s, kapsayici get_attribute; toplam get_attribute #{p['api_total']})"
        (p['top'] || []).each { |k, cnt, t, g| puts format('  %-45s %8d  %8.4f %10d', k, cnt, t, g.to_i) }
        puts "  -- get_attribute'a gore ilk 25 --"
        (p['top_api'] || []).each { |k, cnt, t, g| puts format('  %-45s %8d  %8.4f %10d', k, cnt, t, g.to_i) }
      end
      puts "\n== #{op}: izlenen yontemlerin cagri sayisi n'e gore (#{blocks.map { |b| profs[[b, base]]['n'] }.join('/')}) =="
      WATCH.each do |w|
        row = srcs.keys.map { |c| blocks.map { |b| (profs[[b, c]]['calls'] || {})[w].to_i }.join('/') }
        next if row.all? { |x| x.split('/').all?('0') }
        ga = srcs.keys.map { |c| blocks.map { |b| (profs[[b, c]]['api'] || {})[w].to_i }.join('/') }
        puts format('  %-28s cagri %s=%-16s %s=%-16s | get_attribute %s=%s %s=%s', w, base, row[0], newc, row[1], base, ga[0], newc, ga[1])
      end
      puts "\n== #{op}: cagri sayisi farki (n=#{profs[[blocks.last, base]]['n']}; |fark|>0, buyukten kucuge, ilk 40) =="
      cb = profs[[blocks.last, base]]['calls'] || {}; cn = profs[[blocks.last, newc]]['calls'] || {}
      (cb.keys | cn.keys).map { |k| [k, cb[k].to_i, cn[k].to_i] }.reject { |_, a, b| a == b }
                         .sort_by { |_, a, b| -(b - a).abs }.first(40)
                         .each { |k, a, b| puts format('  %-45s %8d -> %8d', k, a, b) }
    end
  end
end

mode = ARGV[0]
case mode
when 'time', 'prof', 'obs' then child(mode, ARGV[1], ARGV[2].to_i, ARGV[3], ARGV[4])
when 'all', nil
  driver(ARGV[1] || '872d3a3', ARGV[2] || 'c8f9d70', (ARGV[3] || '8,15,30').split(',').map(&:to_i), (ARGV[4] || 3).to_i)
else abort 'kullanim: ruby tools/perf/run_perf.rb all|time|prof ...'
end
