# frozen_string_literal: true

require "test_helper"

class CacheTest < Minitest::Test
  include RSXTest

  def test_static_markup_is_allocated_once
    template = RSX::Template.new("<p class='static'>hello</p>")
    first = template.render
    second = template.render

    assert_same first.to_s, second.to_s
    assert_equal %(<p class="static">hello</p>), first.to_s
  end

  def test_static_component_is_detected_and_memoized
    component = define(<<~RSX, name: "Logo")
      component Logo do |props|
        return (
          <svg viewBox="0 0 16 16">
            <path d="M0 0h16v16H0z" />
          </svg>
        )
      end
    RSX

    assert_predicate component, :rsx_static?
    assert_same component.call.to_s, component.call.to_s
  end

  def test_dynamic_component_is_not_static
    component = define(<<~RSX, name: "Dynamic")
      component Dynamic do |value:|
        return <p>{value}</p>
      end
    RSX

    refute_predicate component, :rsx_static?
  end

  def test_component_level_cache_reuses_output_per_props
    calls = { count: 0 }
    Object.const_set(:CacheProbe, calls)

    component = define(<<~RSX, name: "Cached")
      component Cached, cache: true do |id:|
        CacheProbe[:count] += 1
        return <p>{id}</p>
      end
    RSX

    assert_equal "<p>1</p>", component.call(id: 1).to_s
    assert_equal "<p>1</p>", component.call(id: 1).to_s
    assert_equal 1, calls[:count]

    assert_equal "<p>2</p>", component.call(id: 2).to_s
    assert_equal 2, calls[:count]
  ensure
    Object.send(:remove_const, :CacheProbe) if Object.const_defined?(:CacheProbe, false)
  end

  def test_component_cache_accepts_a_custom_key
    calls = { count: 0 }
    Object.const_set(:CacheProbe, calls)

    component = define(<<~RSX, name: "KeyedCache")
      component KeyedCache, cache: { key: ->(props) { props[:group] } } do |group:, name:|
        CacheProbe[:count] += 1
        return <p>{name}</p>
      end
    RSX

    assert_equal "<p>a</p>", component.call(group: 1, name: "a").to_s
    # Same cache key, so the cached markup is reused even though name changed.
    assert_equal "<p>a</p>", component.call(group: 1, name: "b").to_s
    assert_equal 1, calls[:count]
  ensure
    Object.send(:remove_const, :CacheProbe) if Object.const_defined?(:CacheProbe, false)
  end

  def test_fragment_cache_inside_a_component
    calls = { count: 0 }
    Object.const_set(:CacheProbe, calls)

    component = define(<<~RSX, name: "Fragmented")
      component Fragmented do |id:, label:|
        return (
          <div>
            {cache(["row", id]) do
              CacheProbe[:count] += 1
              <span>{label}</span>
            end}
          </div>
        )
      end
    RSX

    assert_equal "<div><span>a</span></div>", component.call(id: 1, label: "a").to_s
    assert_equal "<div><span>a</span></div>", component.call(id: 1, label: "zzz").to_s
    assert_equal 1, calls[:count]

    assert_equal "<div><span>b</span></div>", component.call(id: 2, label: "b").to_s
    assert_equal 2, calls[:count]
  ensure
    Object.send(:remove_const, :CacheProbe) if Object.const_defined?(:CacheProbe, false)
  end

  def test_cache_store_can_be_replaced
    RSX.config.cache_store = RSX::Cache::Null.new
    calls = { count: 0 }
    Object.const_set(:CacheProbe, calls)

    component = define(<<~RSX, name: "NotCached")
      component NotCached, cache: true do |id:|
        CacheProbe[:count] += 1
        return <p>{id}</p>
      end
    RSX

    component.call(id: 1)
    component.call(id: 1)
    assert_equal 2, calls[:count]
  ensure
    Object.send(:remove_const, :CacheProbe) if Object.const_defined?(:CacheProbe, false)
  end

  def test_memory_store_expires_entries
    store = RSX::Cache::Memory.new
    store.write("k", "v", expires_in: -1)
    assert_nil store.read("k")

    store.write("k", "v", expires_in: 60)
    assert_equal "v", store.read("k")
  end

  def test_memory_store_evicts_least_recently_used
    store = RSX::Cache::Memory.new(max_entries: 2)
    store.write("a", "1")
    store.write("b", "2")
    store.read("a")
    store.write("c", "3")

    assert_equal "1", store.read("a")
    assert_nil store.read("b")
    assert_equal "3", store.read("c")
  end

  def test_compile_cache_writes_and_reuses_ruby
    Dir.mktmpdir do |dir|
      RSX.config.cache_dir = dir
      source = "<p>cached</p>"
      first = RSX.config.compile_cache.fetch_or_compile("demo.rsx", source) { RSX.compile(source) }

      files = Dir.children(dir)
      assert_equal 1, files.length

      # A fresh cache in the same directory reads the file instead of compiling.
      RSX.config.cache_dir = dir
      second = RSX.config.compile_cache.fetch_or_compile("demo.rsx", source) { flunk "recompiled" }
      assert_equal first, second
    end
  end

  def test_precompile_warms_every_file
    Dir.mktmpdir do |dir|
      cache = File.join(dir, "cache")
      File.write(File.join(dir, "a.rsx"), "<p>a</p>\n")
      File.write(File.join(dir, "b.rsx"), "<p>b</p>\n")

      RSX.config.paths = [dir]
      RSX.config.cache_dir = cache
      RSX.precompile!

      assert_equal(2, Dir.children(cache).count { |file| file.end_with?(".rb") })
    end
  end
end
