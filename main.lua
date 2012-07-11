--[[============================================================================

Auto-collapse Groups version 0.1.

Released under a CC-BY license.
http://creativecommons.org/licenses/by/3.0/

http://github.com/jiku/ca.jiku.AutoCollapseGroups.xrnx

============================================================================]]--


-- Globals used throughout
local song = nil
local track = nil
local last_track_index = nil


-- Adds index property to all tracks (i.e. taktik's fun and sneaky way)
local index_property = property(function(self)
  for index, track in ipairs(renoise.song().tracks) do
    if (rawequal(self, track)) then
      return index
    end
  end
end)
renoise.Track.index = index_property 
renoise.GroupTrack.index = index_property 

-- Adds table to group tracks indexing children
local children_property = property(function(self)
    local children = {}
    for index, track in ipairs(renoise.song().tracks) do
      if (rawequal(track.group_parent, self)) then 
        table.insert(children, track.index)
      end
    end
    return children
end)
renoise.GroupTrack.children = children_property

-- Adds table to sequencer and group tracks indexing all ancestors
local ancestors_property = property(function(self)
  local ancestors = {}

  if self.group_parent then
    local i = 1
    ancestors[1] = self.group_parent
    while ancestors[i].group_parent do
      ancestors[i + 1] = ancestors[i].group_parent
      i = i + 1
    end
  end

  return ancestors
end)
renoise.Track.ancestors = ancestors_property
renoise.GroupTrack.ancestors = ancestors_property


function init()
  song = renoise.song()

  add_notifiers()

  -- Collapses all groups initially
  for i = 1, #song.tracks do
    if is_group_track(i) then
      song.tracks[i].group_collapsed = true
    end 
  end
end
 

function selected_track_changed()
  -- Compares last and current track index
  if not track then
    last_track_index = song.selected_track_index
  else
    last_track_index = track.index
  end
  track = song.selected_track

  -- Selects first and most distant descendant if coming from the left
  if is_group_track(track.index) and not is_ancestor(last_track_index, track.index) then
    if track.index > last_track_index or last_track_index == #song.tracks then
      -- Disables notifiers to avoid a notifier feedback loop
      remove_notifiers()
      goto_first_and_most_distant_descendant(track.index)
      add_notifiers()
    end
  end

  -- Collapses last group if leaving it for a track that isn't a descendant 
  if is_group_track(last_track_index) and not is_ancestor(track.index, last_track_index) then
    song.tracks[last_track_index].group_collapsed = true
  end

  -- Collapses any ancestors of the last track that aren't shared if coming from the right
  if not has_same_parent(track.index, last_track_index) and song.tracks[last_track_index].group_parent then
    if track.index < last_track_index or last_track_index == 1 then
      -- Disables notifiers to avoid a notifier feedback loop
      remove_notifiers()
      for index, ancestor in ipairs(song.tracks[last_track_index].ancestors) do      
        -- Doesn't contract when it's a shared ancestor
        if not is_ancestor(track.index, ancestor.index) then
          ancestor.group_collapsed = true
        end
      end
      add_notifiers()
    end
  end

  -- Expands current group if it's contracted
  if is_group_track(track.index) then
    track.group_collapsed = false
  end
end

-- Checks if a given track is a group
function is_group_track(_index)
  if song.tracks[_index].type == renoise.Track.TRACK_TYPE_GROUP then
    return true
  else
    return false
  end
end

-- Selects a given track
function goto_track(_index)
  song.selected_track_index = _index
end

-- Selects the first and most distant descendant of a group
function goto_first_and_most_distant_descendant(_index)
  local first_and_most_distant_descendant_index = nil
  local first_child_index = song.tracks[_index].children[1]

  if first_child_index then
    if is_group_track(first_child_index) then
      local potential_parent = song.tracks[first_child_index]

      while is_group_track(potential_parent.children[1]) do
        potential_parent = song.tracks[potential_parent.children[1]]
      end

      first_and_most_distant_descendant_index = potential_parent.children[1]
    elseif not is_group_track(first_child_index) then
      first_and_most_distant_descendant_index = first_child_index
    end

    goto_track(first_and_most_distant_descendant_index)
  end
end


-- Finds out if a track is the ancestor of another (you can even do phylogenetics with Renoise ;))
function is_ancestor(_index, _potential_ancestor_index)
  for index, ancestor in ipairs(song.tracks[_index].ancestors) do
    if _potential_ancestor_index == ancestor.index then
      return true
    else
    end
  end

  return false
end

-- Compares parent groups
function has_same_parent(_index_1, _index_2)
  if song.tracks[_index_1].group_parent and song.tracks[_index_2].group_parent and (rawequal(song.tracks[_index_1].group_parent, song.tracks[_index_2].group_parent)) then 
    return true
  else
    return false
  end
end

-- Adds/removes notifiers (used on (re-/de)init and to avoid notifier feedback loops)
function add_notifiers()
  if not song.selected_pattern_track_observable:has_notifier(selected_track_changed) then
    song.selected_pattern_track_observable:add_notifier(selected_track_changed)
  end
end
function remove_notifiers()
  if song.selected_pattern_track_observable:has_notifier(selected_track_changed) then
    song.selected_pattern_track_observable:remove_notifier(selected_track_changed)
  end
end

function deinit()
  remove_notifiers()

  song = nil
  track = nil
  last_track_index = nil
end

-- (Re)initializes with new documents
renoise.tool().app_new_document_observable:add_notifier(init)
renoise.tool().app_release_document_observable:add_notifier(deinit)