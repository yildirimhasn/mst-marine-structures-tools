# frozen_string_literal: true
# Dependency caches are derived data. Never use them as relationship evidence.
module MAG
  module MarineStructuresTools
    # Build the relationship graph once. Callers that already collected the
    # model may pass that collection so controlled-change previews do not
    # rescan the entire SketchUp model for every BFS node.
    def dependency_graph(model, source_elements = nil)
      all = source_elements ? source_elements.dup : []
      collect_elements(model.entities, all) unless source_elements
      all = all.select { |e| e.respond_to?(:valid?) && e.valid? }.uniq.sort_by(&:persistent_id)
      children = Hash.new { |h, k| h[k] = [] }
      parents = Hash.new { |h, k| h[k] = [] }
      types = all.group_by { |e| e.get_attribute(DICT, 'element_type', '').to_s }
      by_pid = all.each_with_object({}) { |e, index| index[e.persistent_id] = e }
      by_uid = all.group_by { |e| e.get_attribute(DICT, 'element_uid', '').to_s }
      piles = (types['steel_pipe_pile'] || []).group_by { |e| element_visible_id(e) }
      decks = types['deck_slab'] || []
      deck_ids = decks.group_by { |e| element_visible_id(e) }
      link = lambda do |a, b|
        next unless a && b && a != b
        # Explicit conflicting organization is never bridged.
        next if %w[project ano].any? do |key|
          av = a.get_attribute(DICT, key, '').to_s.strip
          bv = b.get_attribute(DICT, key, '').to_s.strip
          !av.empty? && !bv.empty? && av != bv
        end
        children[a] << b unless children[a].include?(b)
        parents[b] << a unless parents[b].include?(a)
      end
      (types['head_beam'] || []).each do |beam|
        mst_pile_ids_for_beam(beam).each do |id|
          matches = piles[id] || []
          link.call(matches.first, beam) if matches.length == 1
        end
      end
      deck_supports = {}
      decks.each do |deck|
        supports = deck.get_attribute(DICT, 'support_pids', '').to_s.split(',').map(&:to_i).uniq
        supports.select! { |pid| by_pid[pid] && by_pid[pid].get_attribute(DICT, 'element_type') == 'head_beam' }
        deck_supports[deck] = supports
        supports.each { |pid| link.call(by_pid[pid], deck) }
      end
      ((types['flat_precast'] || []) + (types['channel_precast'] || []) + (types['crane_precast'] || [])).each do |precast|
        supports = %w[support_left_pid support_right_pid].map { |k| precast.get_attribute(DICT, k, 0).to_i }.uniq
        supports.each do |pid|
          beam = by_pid[pid]
          link.call(beam, precast) if beam && beam.get_attribute(DICT, 'element_type') == 'head_beam'
        end
        # Both real supports must belong to the deck. No single-deck fallback,
        # no one-common-support guess, and no stale UID/ID cache is consulted.
        next unless supports.length == 2 && supports.all? { |pid| by_pid[pid] && by_pid[pid].get_attribute(DICT, 'element_type') == 'head_beam' }
        decks.each { |deck| link.call(precast, deck) if (supports - deck_supports[deck]).empty? }
      end
      (types['curb'] || []).each do |curb|
        uid = curb.get_attribute(DICT, 'parent_uid', '').to_s
        matches = if uid.empty?
                    deck_ids[curb.get_attribute(DICT, 'parent_deck_id', '').to_s] || []
                  else
                    (by_uid[uid] || []).select { |e| decks.include?(e) }
                  end
        # ADR-0515 §1 / K06: copied deck shares the UID; link the owner only when
        # it is decided by the stored owner or the PID inside the UID (no oldest-PID guess).
        if matches.length > 1
          owner, reason = mst_uid_owner(matches)
          matches = reason == 'en eski PID' ? [] : [owner]
        end
        link.call(matches.first, curb) if matches.length == 1
      end
      [all, children, parents, by_uid]
    end

    # ADR-0515 §1 / K06 (read-only): owner of a duplicated element_uid.
    # Returns [element, reason]; reason: 'kayıtlı sahip' (uid_owner_pid == own
    # persistent_id, single), 'UID içindeki PID' (MST-<pid>- matches, single)
    # or 'en eski PID' (smallest persistent_id).
    def mst_uid_owner(candidates)
      list = Array(candidates).select { |e| e.respond_to?(:persistent_id) }
      return [nil, nil] if list.empty?
      stored = list.select { |e| e.get_attribute(DICT, 'uid_owner_pid', nil).to_i == e.persistent_id }
      return [stored.first, 'kayıtlı sahip'] if stored.length == 1
      in_uid = list.select { |e| e.get_attribute(DICT, 'element_uid', '').to_s[/\AMST-(\d+)-/, 1].to_i == e.persistent_id }
      return [in_uid.first, 'UID içindeki PID'] if in_uid.length == 1
      [list.min_by(&:persistent_id), 'en eski PID']
    end

    def dependency_changes(model)
      all, children, parents, by_uid = dependency_graph(model)
      changes = []
      all.each do |e|
        { 'child' => children[e], 'parent' => parents[e] }.each do |direction, targets|
          targets = targets.sort_by(&:persistent_id)
          # Missing/duplicate identities remain for Audit/Identity Repair; do
          # not manufacture identities or conceal them with a replacement UID.
          uids = targets.map { |x| x.get_attribute(DICT, 'element_uid', '').to_s }.reject(&:empty?).uniq
          values = { "dependency_#{direction}_uids" => uids.join(','),
                     "dependency_#{direction}_ids" => targets.map { |x| element_visible_id(x) }.uniq.join(',') }
          values.each { |k, v| changes << [e, k, v] unless e.get_attribute(DICT, k) == v }
        end
        changes << [e, 'dependency_schema', '2.2'] unless e.get_attribute(DICT, 'dependency_schema') == '2.2'
      end
      unless all.empty?
        { 'dependency_schema_version' => '2.2', 'dependency_revision' => 'v0.23.5.1' }.each do |k, v|
          changes << [model, k, v] unless model.get_attribute(DICT, k) == v
        end
      end
      changes
    end

    def rebuild_dependency_metadata(model = Sketchup.active_model)
      dependency_changes(model).each { |e, k, v| e.set_attribute(DICT, k, v) }
    end

    def refresh_dependency_metadata_inline
      rebuild_dependency_metadata
    end

    # Every plugin operation calls this before committing. No nested operation.
    def commit_with_dependencies(model)
      rebuild_dependency_metadata(model)
      model.commit_operation
    end

    def mst_direct_dependencies(e, all = nil)
      dependency_graph(Sketchup.active_model, all)[1][e]
    end

    def mst_direct_parents(e, all = nil)
      dependency_graph(Sketchup.active_model, all)[2][e]
    end

    # Controlled-change preview traverses a prebuilt graph. This changes only
    # the cost of traversal; dependency rules remain owned by dependency_graph.
    def mst_dependency_tree(root)
      _all, children, _parents, _by_uid = dependency_graph(Sketchup.active_model)
      root_uid = root.get_attribute(DICT, 'element_uid', '').to_s
      root_key = root_uid.empty? ? "pid:#{root.persistent_id}" : root_uid
      seen = { root_key => true }
      queue = [[root, 0]]
      rows = []
      until queue.empty?
        current, depth = queue.shift
        children[current].each do |child|
          uid = child.get_attribute(DICT, 'element_uid', '').to_s
          key = uid.empty? ? "pid:#{child.persistent_id}" : uid
          next if seen[key]
          seen[key] = true
          rows << [child, depth + 1]
          queue << [child, depth + 1]
        end
      end
      rows
    end

    # Native Delete/attribute edits: schedule outside transaction callbacks.
    # Undo/redo cancels pending work; never create edits during undo/redo.
    class DependencyModelObserver < Sketchup::ModelObserver
      def cancel
        UI.stop_timer(@timer) if @timer
        @timer = nil
      end

      def onTransactionCommit(model)
        return if @writing
        cancel
        @timer = UI.start_timer(0, false) do
          @timer = nil
          next unless model.valid? && Sketchup.active_model == model
          changes = MarineStructuresTools.dependency_changes(model)
          next if changes.empty?
          @writing = true
          opened = false
          begin
            model.start_operation('MST Dependency Auto Rebuild', true, false, true)
            opened = true
            changes.each { |e, k, v| e.set_attribute(DICT, k, v) }
          rescue => error
            warn("MST dependency rebuild: #{error.message}")
          ensure
            # A transparent operation must never be aborted (would undo the
            # user's preceding operation). Always close it, even on failure.
            model.commit_operation if opened
            @writing = false
          end
        end
      end

      def onTransactionUndo(model); cancel; end
      def onTransactionRedo(model); cancel; end
      def onTransactionAbort(model); cancel; end
      def onDeleteModel(model); cancel; end
    end

    class DependencyAppObserver < Sketchup::AppObserver
      def expectsStartupModelNotifications; true; end
      def onNewModel(model); MarineStructuresTools.attach_dependency_observer(model); end
      def onOpenModel(model); MarineStructuresTools.attach_dependency_observer(model); end
    end

    def attach_dependency_observer(model)
      @dependency_observers ||= {}
      return if @dependency_observers.key?(model)
      observer = DependencyModelObserver.new
      model.add_observer(observer)
      @dependency_observers[model] = observer
    end

    def install_dependency_observers
      @dependency_app_observer ||= DependencyAppObserver.new
      Sketchup.add_observer(@dependency_app_observer)
      attach_dependency_observer(Sketchup.active_model)
    end
  end
end
