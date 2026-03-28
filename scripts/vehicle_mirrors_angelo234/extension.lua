local M = {}

local im = extensions.ui_imgui
local imUtils = require('ui/imguiUtils')

-- constants
local MIRROR_1_BIT = 1
local MIRROR_2_BIT = 2
local MIRROR_3_BIT = 4

local MODE_OFF = 0
local MODE_WING_MIRRORS = bit.bor(MIRROR_1_BIT, MIRROR_2_BIT)
local MODE_REAR_VIEW_MIRROR = MIRROR_3_BIT
local MODE_ALL_MIRRORS = bit.bor(MIRROR_1_BIT, MIRROR_2_BIT, MIRROR_3_BIT)

local mirrorModesName = {
  [MODE_OFF] = "Off",
  [MODE_WING_MIRRORS] = "Side Mirrors",
  [MODE_REAR_VIEW_MIRROR] = "Rear View Mirror",
  [MODE_ALL_MIRRORS] = "All Mirrors",
}

local windowFlags = im.WindowFlags_NoTitleBar
local uv0, uv1 = im.ImVec2(1,0), im.ImVec2(0,1)
local popupWindowName = 'viewControlRenderViewMirrors'

local mirrorUIsName = {
  "Left Mirror##vehicle_mirrors_angelo234",
  "Right Mirror##vehicle_mirrors_angelo234",
  "Rear View Mirror##vehicle_mirrors_angelo234"
}
local renderViewsName = {
  "render_view_1_vehicle_mirrors_angelo234",
  "render_view_2_vehicle_mirrors_angelo234",
  "render_view_3_vehicle_mirrors_angelo234"
}
local texturesName = {
  "mirror_1_texture_vehicle_mirrors_angelo234",
  "mirror_2_texture_vehicle_mirrors_angelo234",
  "mirror_3_texture_vehicle_mirrors_angelo234"
}
local texObjsPath = {
  '#'..texturesName[1],
  '#'..texturesName[2],
  '#'..texturesName[3]
}

local initViewportSize = im.GetMainViewport().Size

local initWindowsSize = {
  im.ImVec2(250, 250),
  im.ImVec2(250, 250),
  im.ImVec2(500, 150)
}
local initWindowsPos = {
  im.ImVec2(
    initViewportSize.x * 0.05,
    initViewportSize.y * 0.6 - initWindowsSize[1].y * 0.5
  ),
  im.ImVec2(
    initViewportSize.x * 0.95 - initWindowsSize[2].x,
    initViewportSize.y * 0.6 - initWindowsSize[2].y * 0.5
  ),
  im.ImVec2(
    initViewportSize.x * 0.5 - initWindowsSize[3].x * 0.5,
    initViewportSize.y * 0.1
  )
}

local initAspectRatios = {
  initWindowsSize[1].x / initWindowsSize[1].y,
  initWindowsSize[2].x / initWindowsSize[2].y,
  initWindowsSize[3].x / initWindowsSize[3].y
}
local fovs = {math.rad(30), math.rad(30), math.rad(10)}
local nearClip = 0.1

local initMirrorsYaw = {7, -7, 0}
local initMirrorsPitch = {0, 0, 2}
local initMirrorsHorizontalOffset = {0, 0, 0}
local initMirrorsVerticalOffset = {0, 0, 0}

-- non-constants (persistent across Lua reloads)
local lastMode = MODE_OFF
local mode = MODE_OFF
local updateViewsFlag = false

-- false by default as it can cause shadows to flicker
local efficientRendering = false
local resMult = 1.0
local farClip = 250

local mirrorsLastSize = {im.ImVec2(0, 0), im.ImVec2(0, 0), im.ImVec2(0, 0)}
local mirrorsLastAspectRatio = {0, 0, 0}
local mirrorsNodeGroup = {nil, nil}
local mirrorsNodeGroupCount = {0, 0}
local mirrorsRefNodes = {nil, nil}
local mirrorsRotOffset = {nil, nil}
local intMirrorOffsetVec = nil
local mirrorsYaw = {initMirrorsYaw[1], initMirrorsYaw[2], initMirrorsYaw[3]}
local mirrorsPitch = {initMirrorsPitch[1], initMirrorsPitch[2], initMirrorsPitch[3]}
local mirrorsHorizontalOffset = {initMirrorsHorizontalOffset[1], initMirrorsHorizontalOffset[2], initMirrorsHorizontalOffset[3]}
local mirrorsVerticalOffset = {initMirrorsVerticalOffset[1], initMirrorsVerticalOffset[2], initMirrorsVerticalOffset[3]}

local mirrorsYawQuat = {
  quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[1])),
  quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[2])),
  quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[3]))
}
local mirrorsPitchQuat = {
  quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[1])),
  quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[2])),
  quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[3]))
}

local renderViews = {nil, nil, nil}
local frustums = {
  Frustum.construct(false, fovs[1], initAspectRatios[1], nearClip, farClip),
  Frustum.construct(false, fovs[2], initAspectRatios[2], nearClip, farClip),
  Frustum.construct(false, fovs[3], initAspectRatios[3], nearClip, farClip)
}
local resolutions = {
  Point2I(initWindowsSize[1].x * resMult, initWindowsSize[1].y * resMult),
  Point2I(initWindowsSize[2].x * resMult, initWindowsSize[2].y * resMult),
  Point2I(initWindowsSize[3].x * resMult, initWindowsSize[3].y * resMult),
}

local viewports = {
  RectI(0, 0, resolutions[1].x, resolutions[1].y),
  RectI(0, 0, resolutions[2].x, resolutions[2].y),
  RectI(0, 0, resolutions[3].x, resolutions[3].y),
}

local mirrorsYawPtr = {im.FloatPtr(mirrorsYaw[1]), im.FloatPtr(mirrorsYaw[2]), im.FloatPtr(mirrorsYaw[3])}
local mirrorsPitchPtr = {im.FloatPtr(mirrorsPitch[1]), im.FloatPtr(mirrorsPitch[2]), im.FloatPtr(mirrorsPitch[3])}
local mirrorsHorizontalOffsetPtr = {im.FloatPtr(mirrorsHorizontalOffset[1]), im.FloatPtr(mirrorsHorizontalOffset[2]), im.FloatPtr(mirrorsHorizontalOffset[3])}
local mirrorsVerticalOffsetPtr = {im.FloatPtr(mirrorsVerticalOffset[1]), im.FloatPtr(mirrorsVerticalOffset[2]), im.FloatPtr(mirrorsVerticalOffset[3])}
local efficientRenderingPtr = im.BoolPtr(efficientRendering)
local renderDistancePtr = im.IntPtr(farClip / 10)
local resMultPtr = im.FloatPtr(resMult)

local function getMirrorRefNodes(vdata, nodeGroup)
  -- Get left, right, and up nodes to be used to get orientation of mirror
  local leftID, rightID, upID = -1, -1, -1
  local leftMostPos, rightMostPos, upMostPos = math.huge, -math.huge, -math.huge

  for _, nodeID in ipairs(nodeGroup) do
    local x = vdata.nodes[nodeID].pos.x
    if x < leftMostPos then
      leftID = nodeID
      leftMostPos = x
    end
  end
  for _, nodeID in ipairs(nodeGroup) do
    if nodeID ~= leftID then
      local x = vdata.nodes[nodeID].pos.x
      if x > rightMostPos then
        rightID = nodeID
        rightMostPos = x
      end
    end
  end
  for _, nodeID in ipairs(nodeGroup) do
    if nodeID ~= leftID and nodeID ~= rightID then
      local y = vdata.nodes[nodeID].pos.y
      if y > upMostPos then
        upID = nodeID
        upMostPos = y
      end
    end
  end

  if leftID == -1 or rightID == -1 or upID == -1 then return end

  -- Calculate initial rotation offset to have mirror face back of vehicle
  local refNodes = vdata.refNodes[0]
  local ref  = vdata.nodes[refNodes.ref].pos
  local back  = vdata.nodes[refNodes.back].pos
  local up = vdata.nodes[refNodes.up].pos

  local vehBackQuat = quatFromDir((back - ref):normalized(), (up - ref):normalized())

  local leftPos  = vdata.nodes[leftID].pos
  local rightPos  = vdata.nodes[rightID].pos
  local upPos = vdata.nodes[upID].pos

  local mirrorQuat = quatFromDir((rightPos - leftPos):normalized(), (upPos - leftPos):normalized())
  local mirrorRotOffset = vehBackQuat * mirrorQuat:inversed()

  return {leftID, rightID, upID}, mirrorRotOffset
end

-- Hacky algorithm to get mirrors JBeam data,
-- to be used for orienting mirror cameras in realtime
local function getMirrorsInitData()
  -- First find mirror flexbodies (flexbodies mesh names that end with "mirror_L" and "mirror_R")
  local veh = be:getPlayerVehicle(0)
  local vehData = extensions.core_vehicle_manager.getPlayerVehicleData()
  if not veh or not vehData then return end

  local vdata = vehData.vdata
  local leftMirrorFlexbody, rightMirrorFlexbody, intMirrorFlexbody = nil, nil, nil
  local numFound = 0

  for _, flexbody in ipairs(vdata.flexbodies) do
    if not leftMirrorFlexbody and flexbody.mesh:match('_mirror_L') then
      leftMirrorFlexbody = flexbody
      numFound = numFound + 1
    end
    if not rightMirrorFlexbody and flexbody.mesh:match('_mirror_R') then
      rightMirrorFlexbody = flexbody
      numFound = numFound + 1
    end
    if not intMirrorFlexbody
    and flexbody.mesh:match('_int(.*)mirror')
    or flexbody.mesh:match('_ceiling')
    or flexbody.mesh:match('_center_mirror') then
      print(flexbody.mesh)
      intMirrorFlexbody = flexbody
      numFound = numFound + 1
    end

    if numFound == 3 then
      break
    end
  end

  -- Next get mirror JBeam nodes and calculate mirror ref nodes
  local leftNodeGroup, rightNodeGroup
  local leftRefNodes, rightRefNodes
  local leftRotOffset, rightRotOffset
  local intMirrorVec

  if leftMirrorFlexbody then
    local refNodes, rotOffset = getMirrorRefNodes(vdata, leftMirrorFlexbody._group_nodes)
    if refNodes and rotOffset then
      leftNodeGroup = leftMirrorFlexbody._group_nodes
      leftRefNodes = refNodes
      leftRotOffset = rotOffset
    end
  end

  if rightMirrorFlexbody then
    local refNodes, rotOffset = getMirrorRefNodes(vdata, rightMirrorFlexbody._group_nodes)
    if refNodes and rotOffset then
      rightNodeGroup = rightMirrorFlexbody._group_nodes
      rightRefNodes = refNodes
      rightRotOffset = rotOffset
    end
  end

  if intMirrorFlexbody then
    local flexbodyObj = veh:getFlexmesh(intMirrorFlexbody.fid)
    local vertCount = flexbodyObj:getVertexCount()
    local mirrorPos = vec3(0,0,0)

    for j = 0, vertCount - 1 do
      mirrorPos = mirrorPos + flexbodyObj:getInitVertexPos(j)
    end

    mirrorPos = mirrorPos / vertCount
    -- Offset down as mirror mesh includes mirror mount that skews average upwards
    mirrorPos.z = mirrorPos.z - 0.025

    intMirrorVec = mirrorPos - vdata.nodes[vdata.refNodes[0].ref].pos
  end

  return
  leftNodeGroup, leftRefNodes, leftRotOffset,
  rightNodeGroup, rightRefNodes, rightRotOffset,
  intMirrorVec
end

local tempVec1 = vec3(0,0,0)
local tempVec2 = vec3(0,0,0)
local tempVec3 = vec3(0,0,0)
local tempDirVec = vec3(0,0,0)
local tempUpVec = vec3(0,0,0)
local tempVehPos = vec3(0,0,0)
local tempQuat = QuatF(0,0,0,1)

local function getMirrorOrientation(veh, mirrorID, outMat)
  tempVehPos:set(veh:getPositionXYZ())

  if mirrorID == 1 or mirrorID == 2 then
    -- For wing mirrors
    local mirrorRefNodes = mirrorsRefNodes[mirrorID]

    -- right - left
    tempVec1:set(veh:getNodePositionXYZ(mirrorRefNodes[1]))
    tempVec2:set(veh:getNodePositionXYZ(mirrorRefNodes[2]))
    tempDirVec:setSub2(tempVec2, tempVec1)

    -- up - left
    tempVec2:set(veh:getNodePositionXYZ(mirrorRefNodes[3]))
    tempUpVec:setSub2(tempVec2, tempVec1)

    tempDirVec:normalize()
    tempUpVec:normalize()

    local mirQuat = quatFromDir(tempDirVec, tempUpVec)
    mirQuat = mirrorsYawQuat[mirrorID] * mirrorsPitchQuat[mirrorID] * mirrorsRotOffset[mirrorID] * mirQuat
    tempQuat.x, tempQuat.y, tempQuat.z, tempQuat.w = mirQuat.x, mirQuat.y, mirQuat.z, mirQuat.w

    -- Get the position of the mirror
    -- by getting average position of the mirror nodes
    tempVec1:set(0,0,0)
    for _, nodeID in ipairs(mirrorsNodeGroup[mirrorID]) do
      tempVec2:set(veh:getNodePositionXYZ(nodeID))
      tempVec1:setAdd(tempVec2)
    end
    tempVec1:setScaled(1 / mirrorsNodeGroupCount[mirrorID])
    if mirrorsHorizontalOffset[mirrorID] ~= 0 then
      tempVec2:set(tempDirVec)
      tempVec2:setScaled(mirrorsHorizontalOffset[mirrorID])
      tempVec1:setAdd(tempVec2)
    end
    if mirrorsVerticalOffset[mirrorID] ~= 0 then
      tempVec2:set(tempUpVec)
      tempVec2:setScaled(mirrorsVerticalOffset[mirrorID])
      tempVec1:setAdd(tempVec2)
    end
    tempVec1:setAdd(tempVehPos)

    outMat:setFromQuatF(tempQuat)
    outMat:setPosition(tempVec1)

    --debugDrawer:drawSphere(tempVehPos + veh:getNodePosition(mirrorRefNodes[1]), 0.01, ColorF(1,0,0,1))
    --debugDrawer:drawSphere(tempVehPos + veh:getNodePosition(mirrorRefNodes[2]), 0.01, ColorF(0,1,0,1))
    --debugDrawer:drawSphere(tempVehPos + veh:getNodePosition(mirrorRefNodes[3]), 0.01, ColorF(0,0,1,1))
  else
    -- Different calculation for interior mirror
    local vehBackQuat = veh:getRefNodeRotation()
    local mirQuat = mirrorsYawQuat[mirrorID] * mirrorsPitchQuat[mirrorID] * vehBackQuat
    tempQuat.x, tempQuat.y, tempQuat.z, tempQuat.w = mirQuat.x, mirQuat.y, mirQuat.z, mirQuat.w
    tempVec1:setAdd2(vehBackQuat:mulP(intMirrorOffsetVec), tempVehPos)
    if mirrorsHorizontalOffset[mirrorID] ~= 0 or mirrorsVerticalOffset[mirrorID] ~= 0 then
      tempVec2:set(mirrorsHorizontalOffset[mirrorID], 0, mirrorsVerticalOffset[mirrorID])
      tempVec3:setAdd2(vehBackQuat:mulP(tempVec2), tempVec1)
      tempVec1:set(tempVec3)
    end

    outMat:setFromQuatF(tempQuat)
    outMat:setPosition(tempVec1)
  end

  return outMat
end

local mirrorMat = MatrixF(true)
local mirrorsActiveList = {}
local mirrorListIdx = 1

-- Updates position and rotation of cameras (mirrors)
local function onPreRender(dt)
  local veh = be:getPlayerVehicle(0)
  if not veh then return end

  if efficientRendering then
    if renderViews[1] then
      -- alternate rendering between mirrors

      table.clear(mirrorsActiveList)

      if bit.band(mode, MIRROR_1_BIT) ~= 0 and mirrorsNodeGroup[1] then table.insert(mirrorsActiveList, 1) end
      if bit.band(mode, MIRROR_2_BIT) ~= 0 and mirrorsNodeGroup[2] then table.insert(mirrorsActiveList, 2) end
      if bit.band(mode, MIRROR_3_BIT) ~= 0 and intMirrorOffsetVec then table.insert(mirrorsActiveList, 3) end

      if mirrorsActiveList[1] then
        mirrorListIdx = mirrorListIdx + 1
        if mirrorListIdx > #mirrorsActiveList then
          mirrorListIdx = 1
        end

        local mirrorToRender = mirrorsActiveList[mirrorListIdx]
        getMirrorOrientation(veh, mirrorToRender, mirrorMat)

        renderViews[1].resolution = resolutions[mirrorToRender]
        renderViews[1].viewport = viewports[mirrorToRender]
        renderViews[1].frustum = frustums[mirrorToRender]
        renderViews[1].cameraMatrix = mirrorMat
        renderViews[1].namedTexTargetColor = texturesName[mirrorToRender]
      end
    end
  else
    if renderViews[1] and mirrorsNodeGroup[1] and bit.band(mode, MIRROR_1_BIT) ~= 0 then
      getMirrorOrientation(veh, 1, mirrorMat)
      renderViews[1].resolution = resolutions[1]
      renderViews[1].viewport = viewports[1]
      renderViews[1].frustum = frustums[1]
      renderViews[1].cameraMatrix = mirrorMat
      renderViews[1].namedTexTargetColor = texturesName[1]
    end
    if renderViews[2] and mirrorsNodeGroup[2] and bit.band(mode, MIRROR_2_BIT) ~= 0 then
      getMirrorOrientation(veh, 2, mirrorMat)
      renderViews[2].cameraMatrix = mirrorMat
    end
    if renderViews[3] and intMirrorOffsetVec and bit.band(mode, MIRROR_3_BIT) ~= 0 then
      getMirrorOrientation(veh, 3, mirrorMat)
      renderViews[3].cameraMatrix = mirrorMat
    end
  end
end

-- Pop-up to adjust render settings
local function renderPopUpViewControl(mirrorID)
  if im.BeginPopup(popupWindowName) then
    if im.BeginMenu('Yaw Angle') then
      local yawAnglePtr = mirrorsYawPtr[mirrorID]

      im.PushItemWidth(100)
      if im.SliderFloat("##yawAngleSlider", yawAnglePtr, -30, 30, "%.1f degrees") then
        mirrorsYaw[mirrorID] = yawAnglePtr[0]
        mirrorsYawQuat[mirrorID] = quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[mirrorID]))
      end

      im.PopItemWidth()
      im.EndMenu()
    end
    if im.BeginMenu('Pitch Angle') then
      local pitchAnglePtr = mirrorsPitchPtr[mirrorID]

      im.PushItemWidth(100)
      if im.SliderFloat("##pitchAngleSlider", pitchAnglePtr, -30, 30, "%.1f degrees") then
        mirrorsPitch[mirrorID] = pitchAnglePtr[0]
        mirrorsPitchQuat[mirrorID] = quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[mirrorID]))
      end

      im.PopItemWidth()
      im.EndMenu()
    end
    if im.BeginMenu('Horizontal Position') then
      local horizontalOffsetPtr = mirrorsHorizontalOffsetPtr[mirrorID]

      im.PushItemWidth(100)
      if im.SliderFloat("##horizontalOffsetSlider", horizontalOffsetPtr, -0.5, 0.5, "%.2f m") then
        mirrorsHorizontalOffset[mirrorID] = horizontalOffsetPtr[0]
      end

      im.PopItemWidth()
      im.EndMenu()
    end
    if im.BeginMenu('Vertical Position') then
      local verticalOffsetPtr = mirrorsVerticalOffsetPtr[mirrorID]

      im.PushItemWidth(100)
      if im.SliderFloat("##verticalOffsetSlider", verticalOffsetPtr, -0.5, 0.5, "%.2f m") then
        mirrorsVerticalOffset[mirrorID] = verticalOffsetPtr[0]
      end

      im.PopItemWidth()
      im.EndMenu()
    end
    im.Separator()
    if im.BeginMenu('Rendering Settings') then
      if im.BeginMenu('Render Distance') then
        im.PushItemWidth(100)
        if im.SliderInt("##renderDistanceSlider", renderDistancePtr, 1, 100, "%d0 m") then
          farClip = renderDistancePtr[0] * 10

          frustums[1] = Frustum.construct(false, fovs[1], mirrorsLastAspectRatio[1], nearClip, farClip)
          frustums[2] = Frustum.construct(false, fovs[2], mirrorsLastAspectRatio[2], nearClip, farClip)
          frustums[3] = Frustum.construct(false, fovs[3], mirrorsLastAspectRatio[3], nearClip, farClip)

          if renderViews[1] then
            renderViews[1].frustum = frustums[1]
          end
          if renderViews[2] then
            renderViews[2].frustum = frustums[2]
          end
          if renderViews[3] then
            renderViews[3].frustum = frustums[3]
          end
        end

        im.PopItemWidth()
        im.EndMenu()
      end
      if im.BeginMenu('Resolution') then
        im.PushItemWidth(100)
        if im.SliderFloat("##resolutionSlider", resMultPtr, 0.1, 2, "%.1fx") then
          resMult = resMultPtr[0]

          for i = 1,3 do
            resolutions[i].x = mirrorsLastSize[i].x * resMult
            resolutions[i].y = mirrorsLastSize[i].y * resMult
            viewports[i]:set(0, 0, resolutions[i].x, resolutions[i].y)

            if renderViews[i] then
              renderViews[i].resolution = resolutions[i]
              renderViews[i].viewPort = viewports[i]
            end
          end
        end

        im.PopItemWidth()
        im.EndMenu()
      end
      if im.Checkbox("Use Efficient Rendering", efficientRenderingPtr) then
        efficientRendering = efficientRenderingPtr[0]
        updateViewsFlag = true
      end
      if im.IsItemHovered() then
        im.BeginTooltip()
        im.Text("Enabled renders a mirror every other frame (not smooth but higher FPS, flickering may occur).\nDisabled renders a mirror every frame (smooth but lower FPS).")
        im.EndTooltip()
      end

      im.EndMenu()
    end

    im.EndPopup()
  end
end

local function renderMirrorWindow(id)
  im.SetNextWindowPos(initWindowsPos[id], im.Cond_FirstUseEver)
  im.SetNextWindowSize(initWindowsSize[id], im.Cond_FirstUseEver)
  if im.Begin(mirrorUIsName[id], nil, windowFlags) then
    renderPopUpViewControl(id)
    local viewSize = im.GetContentRegionAvail()

    if (efficientRendering and renderViews[1]) or renderViews[id] then
      local texObj = imUtils.texObj(texObjsPath[id])
      im.Image(texObj.texId, viewSize, uv0, uv1)

      if im.IsItemClicked(1) then
        im.OpenPopup(popupWindowName)
      end

      local wndSize = im.GetWindowSize()

      if wndSize.x ~= mirrorsLastSize[id].x or wndSize.y ~= mirrorsLastSize[id].y then
        resolutions[id].x = wndSize.x * resMult
        resolutions[id].y = wndSize.y * resMult
        viewports[id]:set(0, 0, resolutions[id].x, resolutions[id].y)

        local aspectRatio = wndSize.x / wndSize.y
        frustums[id] = Frustum.construct(false, fovs[id], aspectRatio, nearClip, farClip)

        if not efficientRendering and renderViews[id] then
          renderViews[id].resolution = resolutions[id]
          renderViews[id].viewPort = viewports[id]
          renderViews[id].frustum = frustums[id]
        end

        mirrorsLastAspectRatio[id] = aspectRatio
        mirrorsLastSize[id] = wndSize
      end
    else
      im.TextUnformatted('View Broken')
    end

    im.End()
  end
end

-- Show the mirror images on the imgui windows
local function renderImGui()
  if bit.band(mode, MIRROR_1_BIT) ~= 0 and mirrorsNodeGroup[1] then renderMirrorWindow(1) end
  if bit.band(mode, MIRROR_2_BIT) ~= 0 and mirrorsNodeGroup[2] then renderMirrorWindow(2) end
  if bit.band(mode, MIRROR_3_BIT) ~= 0 and intMirrorOffsetVec then renderMirrorWindow(3) end
end

local function initMirrorView(id)
  if not renderViews[id] then
    renderViews[id] = RenderViewManagerInstance:getOrCreateView(renderViewsName[id])
    renderViews[id].renderCubemap = false
    renderViews[id].cameraMatrix = MatrixF(true) -- determines where the virtual camera is in 3d space
    renderViews[id].resolution = resolutions[id]
    renderViews[id].viewPort = viewports[id]
    renderViews[id].namedTexTargetColor = texturesName[id] -- important: the target texture, used in texObj
    renderViews[id].frustum = frustums[id]
    renderViews[id].fov = fovs[id]
    renderViews[id].renderEditorIcons = false
  end
end

local function destroyView(id)
  if renderViews[id] then
    RenderViewManagerInstance:destroyView(renderViews[id])
    renderViews[id] = nil
  end
end

local function onUpdate(dt)
  local veh = be:getPlayerVehicle(0)
  if not veh then return end

  -- Destroy views when not showing mirrors
  if mode ~= lastMode or updateViewsFlag then
    if efficientRendering then
      if mode ~= MODE_OFF and (mirrorsNodeGroup[1] or mirrorsNodeGroup[2] or intMirrorOffsetVec) then
        initMirrorView(1)
      else
        destroyView(1)
      end
      destroyView(2)
      destroyView(3)
    else
      if bit.band(mode, MIRROR_1_BIT) ~= 0 and mirrorsNodeGroup[1] then initMirrorView(1) else destroyView(1) end
      if bit.band(mode, MIRROR_2_BIT) ~= 0 and mirrorsNodeGroup[2] then initMirrorView(2) else destroyView(2) end
      if bit.band(mode, MIRROR_3_BIT) ~= 0 and intMirrorOffsetVec then initMirrorView(3) else destroyView(3) end
    end

    updateViewsFlag = false
  end

  -- Render the mirrors in imgui windows
  renderImGui()

  lastMode = mode
end

local function resetMirrorAdjustments()
  mirrorsYaw[1], mirrorsYaw[2], mirrorsYaw[3] = initMirrorsYaw[1], initMirrorsYaw[2], initMirrorsYaw[3]
  mirrorsPitch[1], mirrorsPitch[2], mirrorsPitch[3] = initMirrorsPitch[1], initMirrorsPitch[2], initMirrorsPitch[3]
  mirrorsHorizontalOffset[1], mirrorsHorizontalOffset[2], mirrorsHorizontalOffset[3] = initMirrorsHorizontalOffset[1], initMirrorsHorizontalOffset[2], initMirrorsHorizontalOffset[3]
  mirrorsVerticalOffset[1], mirrorsVerticalOffset[2], mirrorsVerticalOffset[3] = initMirrorsVerticalOffset[1], initMirrorsVerticalOffset[2], initMirrorsVerticalOffset[3]

  mirrorsYawQuat[1] = quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[1]))
  mirrorsPitchQuat[1] = quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[1]))
  mirrorsYawQuat[2] = quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[2]))
  mirrorsPitchQuat[2] = quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[2]))
  mirrorsYawQuat[3] = quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[3]))
  mirrorsPitchQuat[3] = quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[3]))

  mirrorsYawPtr[1], mirrorsYawPtr[2], mirrorsYawPtr[3] = im.FloatPtr(mirrorsYaw[1]), im.FloatPtr(mirrorsYaw[2]), im.FloatPtr(mirrorsYaw[3])
  mirrorsPitchPtr[1], mirrorsPitchPtr[2], mirrorsPitchPtr[3] = im.FloatPtr(mirrorsPitch[1]), im.FloatPtr(mirrorsPitch[2]), im.FloatPtr(mirrorsPitch[3])
  mirrorsHorizontalOffsetPtr[1], mirrorsHorizontalOffsetPtr[2], mirrorsHorizontalOffsetPtr[3] = im.FloatPtr(mirrorsHorizontalOffset[1]), im.FloatPtr(mirrorsHorizontalOffset[2]), im.FloatPtr(mirrorsHorizontalOffset[3])
  mirrorsVerticalOffsetPtr[1], mirrorsVerticalOffsetPtr[2], mirrorsVerticalOffsetPtr[3] = im.FloatPtr(mirrorsVerticalOffset[1]), im.FloatPtr(mirrorsVerticalOffset[2]), im.FloatPtr(mirrorsVerticalOffset[3])
end

local function onVehicleSwitched(oldId, newId, player, secondTime)
  mirrorsNodeGroup[1], mirrorsNodeGroup[2] = nil, nil
  mirrorsRefNodes[1], mirrorsRefNodes[2] = nil, nil
  mirrorsNodeGroupCount[1], mirrorsNodeGroupCount[2] = nil, nil
  intMirrorOffsetVec = nil

  resetMirrorAdjustments()

  -- Super hacky temporary way to make sure flexmeshes are initialized by delaying setup
  if not secondTime then
    local veh = be:getPlayerVehicle(0)
    if veh then
      veh:queueLuaCommand("obj:queueGameEngineLua('scripts_vehicle__mirrors__angelo234_extension.onVehicleSwitched(" .. oldId .. "," .. newId .. "," .. player .. ", true)')")
    end
    return
  end

  if newId ~= -1 then
    mirrorsNodeGroup[1],
    mirrorsRefNodes[1],
    mirrorsRotOffset[1],
    mirrorsNodeGroup[2],
    mirrorsRefNodes[2],
    mirrorsRotOffset[2],
    intMirrorOffsetVec = getMirrorsInitData()

    if mirrorsNodeGroup[1] then
      mirrorsNodeGroupCount[1] = #mirrorsNodeGroup[1]
    end
    if mirrorsNodeGroup[2] then
      mirrorsNodeGroupCount[2] = #mirrorsNodeGroup[2]
    end
  end

  updateViewsFlag = true
end

local function toggleMirrorsUI()
  if mode == MODE_OFF then
    mode = MODE_WING_MIRRORS
  elseif mode == MODE_WING_MIRRORS then
    mode = MODE_REAR_VIEW_MIRROR
  elseif mode == MODE_REAR_VIEW_MIRROR then
    mode = MODE_ALL_MIRRORS
  elseif mode == MODE_ALL_MIRRORS then
    mode = MODE_OFF
  end

  guihooks.message("Mirror Mode: " .. mirrorModesName[mode], 5, "mirror_mode_vehicle_mirrors_angelo234", nil)
end

local function onExtensionLoaded()
end

local function onExtensionUnloaded()
  destroyView(1)
  destroyView(2)
  destroyView(3)
end

local function onSerialize()
  local data = {}

  data.mode = mode
  data.efficientRendering = efficientRendering
  data.resMult = resMult
  data.farClip = farClip

  data.mirrorsNodeGroup = mirrorsNodeGroup
  data.mirrorsNodeGroupCount = mirrorsNodeGroupCount
  data.mirrorsRefNodes = mirrorsRefNodes
  data.mirrorsRotOffset = mirrorsRotOffset
  data.intMirrorOffsetVec = intMirrorOffsetVec

  data.mirrorsYaw = mirrorsYaw
  data.mirrorsPitch = mirrorsPitch
  data.mirrorsHorizontalOffset = mirrorsHorizontalOffset
  data.mirrorsVerticalOffset = mirrorsVerticalOffset

  return data
end

local function onDeserialized(data)
  mode = data.mode
  efficientRendering = data.efficientRendering
  resMult = data.resMult
  farClip = data.farClip

  mirrorsNodeGroup = data.mirrorsNodeGroup
  mirrorsNodeGroupCount = data.mirrorsNodeGroupCount
  mirrorsRefNodes = data.mirrorsRefNodes
  mirrorsRotOffset = data.mirrorsRotOffset
  intMirrorOffsetVec = data.intMirrorOffsetVec

  mirrorsYaw = data.mirrorsYaw
  mirrorsPitch = data.mirrorsPitch
  mirrorsHorizontalOffset = data.mirrorsHorizontalOffset or {initMirrorsHorizontalOffset[1], initMirrorsHorizontalOffset[2], initMirrorsHorizontalOffset[3]}
  mirrorsVerticalOffset = data.mirrorsVerticalOffset or {initMirrorsVerticalOffset[1], initMirrorsVerticalOffset[2], initMirrorsVerticalOffset[3]}

  -- Calculate mirror angle quats from the saved angles
  mirrorsYawQuat[1] = quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[1]))
  mirrorsPitchQuat[1] = quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[1]))
  mirrorsYawQuat[2] = quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[2]))
  mirrorsPitchQuat[2] = quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[2]))
  mirrorsYawQuat[3] = quatFromAxisAngle(vec3(0,0,1), math.rad(mirrorsYaw[3]))
  mirrorsPitchQuat[3] = quatFromAxisAngle(vec3(1,0,0), math.rad(mirrorsPitch[3]))

  -- Set the mirror settings pointers
  efficientRenderingPtr = im.BoolPtr(efficientRendering)
  mirrorsYawPtr[1], mirrorsYawPtr[2], mirrorsYawPtr[3] = im.FloatPtr(mirrorsYaw[1]), im.FloatPtr(mirrorsYaw[2]), im.FloatPtr(mirrorsYaw[3])
  mirrorsPitchPtr[1], mirrorsPitchPtr[2], mirrorsPitchPtr[3] = im.FloatPtr(mirrorsPitch[1]), im.FloatPtr(mirrorsPitch[2]), im.FloatPtr(mirrorsPitch[3])
  mirrorsHorizontalOffsetPtr[1], mirrorsHorizontalOffsetPtr[2], mirrorsHorizontalOffsetPtr[3] = im.FloatPtr(mirrorsHorizontalOffset[1]), im.FloatPtr(mirrorsHorizontalOffset[2]), im.FloatPtr(mirrorsHorizontalOffset[3])
  mirrorsVerticalOffsetPtr[1], mirrorsVerticalOffsetPtr[2], mirrorsVerticalOffsetPtr[3] = im.FloatPtr(mirrorsVerticalOffset[1]), im.FloatPtr(mirrorsVerticalOffset[2]), im.FloatPtr(mirrorsVerticalOffset[3])
  renderDistancePtr = im.IntPtr(farClip / 10)
  resMultPtr = im.FloatPtr(resMult)

  updateViewsFlag = true
end

M.onPreRender = onPreRender
M.onUpdate = onUpdate
M.onVehicleSwitched = onVehicleSwitched
M.toggleMirrorsUI = toggleMirrorsUI
M.onExtensionLoaded = onExtensionLoaded
M.onExtensionUnloaded = onExtensionUnloaded
M.onSerialize = onSerialize
M.onDeserialized = onDeserialized

return M
