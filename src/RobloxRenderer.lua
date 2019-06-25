--[[
	Renderer that deals in terms of Roblox Instances. This is the most
	well-supported renderer after NoopRenderer and is currently the only
	renderer that does anything.
]]

local Binding = require(script.Parent.Binding)
local Children = require(script.Parent.PropMarkers.Children)
local ElementKind = require(script.Parent.ElementKind)
local SingleEventManager = require(script.Parent.SingleEventManager)
local getDefaultInstanceProperty = require(script.Parent.getDefaultInstanceProperty)
local Ref = require(script.Parent.PropMarkers.Ref)
local Type = require(script.Parent.Type)
local internalAssert = require(script.Parent.internalAssert)

local config = require(script.Parent.GlobalConfig).get()

local applyPropsError = [[
Error applying props:
	%s
In element:
%s
]]

local updatePropsError = [[
Error updating props:
	%s
In element:
%s
]]

local function identity(...)
	return ...
end

local function applyRef(ref, newHostObject)
	if ref == nil then
		return
	end

	if typeof(ref) == "function" then
		ref(newHostObject)
	elseif Type.of(ref) == Type.Binding then
		Binding.update(ref, newHostObject)
	else
		-- TODO (#197): Better error message
		error(("Invalid ref: Expected type Binding but got %s"):format(
			typeof(ref)
		))
	end
end

local function setRobloxInstanceProperty(hostObject, key, newValue)
	if newValue == nil then
		local hostClass = hostObject.ClassName
		local _, defaultValue = getDefaultInstanceProperty(hostClass, key)
		newValue = defaultValue
	end

	-- Assign the new value to the object
	hostObject[key] = newValue

	return
end

local function removeBinding(virtualNode, key)
	local disconnect = virtualNode.bindings[key]
	disconnect()
	virtualNode.bindings[key] = nil
end

local function attachBinding(virtualNode, key, newBinding)
	local function updateBoundProperty(newValue)
		local success, errorMessage = xpcall(function()
			setRobloxInstanceProperty(virtualNode.hostObject, key, newValue)
		end, identity)

		if not success then
			local source = virtualNode.currentElement.source

			if source == nil then
				source = "<enable element tracebacks>"
			end

			local fullMessage = updatePropsError:format(errorMessage, source)
			error(fullMessage, 0)
		end
	end

	if virtualNode.bindings == nil then
		virtualNode.bindings = {}
	end

	virtualNode.bindings[key] = Binding.subscribe(newBinding, updateBoundProperty)

	updateBoundProperty(newBinding:getValue())
end

local function detachAllBindings(virtualNode)
	if virtualNode.bindings ~= nil then
		for _, disconnect in pairs(virtualNode.bindings) do
			disconnect()
		end
	end
end

local function applyProp(virtualNode, key, newValue, oldValue)
	if newValue == oldValue then
		return
	end

	if key == Ref or key == Children then
		-- Refs and children are handled in a separate pass
		return
	end

	local internalKeyType = Type.of(key)

	if internalKeyType == Type.HostEvent or internalKeyType == Type.HostChangeEvent then
		if virtualNode.eventManager == nil then
			virtualNode.eventManager = SingleEventManager.new(virtualNode.hostObject)
		end

		local eventName = key.name

		if internalKeyType == Type.HostChangeEvent then
			virtualNode.eventManager:connectPropertyChange(eventName, newValue)
		else
			virtualNode.eventManager:connectEvent(eventName, newValue)
		end

		return
	end

	local newIsBinding = Type.of(newValue) == Type.Binding
	local oldIsBinding = Type.of(oldValue) == Type.Binding

	if oldIsBinding then
		removeBinding(virtualNode, key)
	end

	if newIsBinding then
		attachBinding(virtualNode, key, newValue)
	else
		setRobloxInstanceProperty(virtualNode.hostObject, key, newValue)
	end
end

local function applyProps(virtualNode, props)
	for propKey, value in pairs(props) do
		applyProp(virtualNode, propKey, value, nil)
	end
end

local function updateProps(virtualNode, oldProps, newProps)
	-- Apply props that were added or updated
	for propKey, newValue in pairs(newProps) do
		local oldValue = oldProps[propKey]

		applyProp(virtualNode, propKey, newValue, oldValue)
	end

	-- Clean up props that were removed
	for propKey, oldValue in pairs(oldProps) do
		local newValue = newProps[propKey]

		if newValue == nil then
			applyProp(virtualNode, propKey, nil, oldValue)
		end
	end
end

local RobloxRenderer = {}

function RobloxRenderer.isHostObject(target)
	return typeof(target) == "Instance"
end

function RobloxRenderer.mountVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement
	local kind = ElementKind.of(element)

	if kind == ElementKind.Host then
		RobloxRenderer._mountHostNode(reconciler, virtualNode)
	elseif kind == ElementKind.Function then
		RobloxRenderer._mountFunctionVirtualNode(reconciler, virtualNode)
	elseif kind == ElementKind.Stateful then
		element.component:__mount(reconciler, virtualNode)
	elseif kind == ElementKind.Portal then
		RobloxRenderer._mountPortalVirtualNode(reconciler, virtualNode)
	elseif kind == ElementKind.Fragment then
		RobloxRenderer._mountFragmentVirtualNode(reconciler, virtualNode)
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end
end

function RobloxRenderer.updateVirtualNode(reconciler, virtualNode, newElement, newState)
	local kind = ElementKind.of(newElement)

	local shouldContinueUpdate = true

	if kind == ElementKind.Host then
		virtualNode = RobloxRenderer._updateHostNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Function then
		virtualNode = RobloxRenderer._updateFunctionVirtualNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Stateful then
		shouldContinueUpdate = virtualNode.instance:__update(newElement, newState)
	elseif kind == ElementKind.Portal then
		virtualNode = RobloxRenderer._updatePortalVirtualNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Fragment then
		virtualNode = RobloxRenderer._updateFragmentVirtualNode(reconciler, virtualNode, newElement)
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end

	if shouldContinueUpdate then
		virtualNode.currentElement = newElement
	end

	return virtualNode
end

function RobloxRenderer.unmountVirtualNode(virtualNode)
	if config.internalTypeChecks then
		internalAssert(Type.of(virtualNode) == Type.VirtualNode, "Expected arg #1 to be of type VirtualNode")
	end

	local kind = ElementKind.of(virtualNode.currentElement)

	if kind == ElementKind.Host then
		RobloxRenderer._unmountHostNode(virtualNode)
	elseif kind == ElementKind.Function then
		for _, childNode in pairs(virtualNode.children) do
			RobloxRenderer.unmountVirtualNode(childNode)
		end
	elseif kind == ElementKind.Stateful then
		virtualNode.instance:__unmount()
	elseif kind == ElementKind.Portal then
		for _, childNode in pairs(virtualNode.children) do
			RobloxRenderer.unmountVirtualNode(childNode)
		end
	elseif kind == ElementKind.Fragment then
		for _, childNode in pairs(virtualNode.children) do
			RobloxRenderer.unmountVirtualNode(childNode)
		end
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end
end

function RobloxRenderer._mountHostNode(reconciler, virtualNode)
	local element = virtualNode.currentElement
	local hostParent = virtualNode.hostParent
	local hostKey = virtualNode.hostKey

	if config.internalTypeChecks then
		internalAssert(ElementKind.of(element) == ElementKind.Host, "Element at given node is not a host Element")
	end
	if config.typeChecks then
		assert(element.props.Name == nil, "Name can not be specified as a prop to a host component in Roact.")
		assert(element.props.Parent == nil, "Parent can not be specified as a prop to a host component in Roact.")
	end

	local instance = Instance.new(element.component)
	virtualNode.hostObject = instance

	local success, errorMessage = xpcall(function()
		applyProps(virtualNode, element.props)
	end, identity)

	if not success then
		local source = element.source

		if source == nil then
			source = "<enable element tracebacks>"
		end

		local fullMessage = applyPropsError:format(errorMessage, source)
		error(fullMessage, 0)
	end

	instance.Name = tostring(hostKey)

	local children = element.props[Children]

	if children ~= nil then
		reconciler.updateVirtualNodeWithChildren(virtualNode, virtualNode.hostObject, children)
	end

	instance.Parent = hostParent
	virtualNode.hostObject = instance

	applyRef(element.props[Ref], instance)

	if virtualNode.eventManager ~= nil then
		virtualNode.eventManager:resume()
	end
end

function RobloxRenderer._unmountHostNode(virtualNode)
	local element = virtualNode.currentElement

	applyRef(element.props[Ref], nil)

	for _, childNode in pairs(virtualNode.children) do
		RobloxRenderer.unmountVirtualNode(childNode)
	end

	detachAllBindings(virtualNode)

	virtualNode.hostObject:Destroy()
end

function RobloxRenderer._mountFunctionVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement

	local children = element.component(element.props)

	reconciler.updateVirtualNodeWithRenderResult(virtualNode, virtualNode.hostParent, children)
end

function RobloxRenderer._mountPortalVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement

	local targetHostParent = element.props.target
	local children = element.props[Children]

	assert(RobloxRenderer.isHostObject(targetHostParent), "Expected target to be host object")

	reconciler.updateVirtualNodeWithChildren(virtualNode, targetHostParent, children)
end

function RobloxRenderer._mountFragmentVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement
	local children = element.elements

	reconciler.updateVirtualNodeWithChildren(virtualNode, virtualNode.hostParent, children)
end

function RobloxRenderer._updateHostNode(reconciler, virtualNode, newElement)
	local oldProps = virtualNode.currentElement.props
	local newProps = newElement.props

	if virtualNode.eventManager ~= nil then
		virtualNode.eventManager:suspend()
	end

	-- If refs changed, detach the old ref and attach the new one
	if oldProps[Ref] ~= newProps[Ref] then
		applyRef(oldProps[Ref], nil)
		applyRef(newProps[Ref], virtualNode.hostObject)
	end

	local success, errorMessage = xpcall(function()
		updateProps(virtualNode, oldProps, newProps)
	end, identity)

	if not success then
		local source = newElement.source

		if source == nil then
			source = "<enable element tracebacks>"
		end

		local fullMessage = updatePropsError:format(errorMessage, source)
		error(fullMessage, 0)
	end

	local children = newElement.props[Children]
	if children ~= nil or oldProps[Children] ~= nil then
		reconciler.updateVirtualNodeWithChildren(virtualNode, virtualNode.hostObject, children)
	end

	if virtualNode.eventManager ~= nil then
		virtualNode.eventManager:resume()
	end

	return virtualNode
end

function RobloxRenderer._updateFunctionVirtualNode(reconciler, virtualNode, newElement)
	local children = newElement.component(newElement.props)

	reconciler.updateVirtualNodeWithRenderResult(virtualNode, virtualNode.hostParent, children)

	return virtualNode
end

function RobloxRenderer._updatePortalVirtualNode(reconciler, virtualNode, newElement)
	local oldElement = virtualNode.currentElement
	local oldTargetHostParent = oldElement.props.target

	local targetHostParent = newElement.props.target

	assert(RobloxRenderer.isHostObject(targetHostParent), "Expected target to be host object")

	if targetHostParent ~= oldTargetHostParent then
		return reconciler.replaceVirtualNode(virtualNode, newElement)
	end

	local children = newElement.props[Children]

	reconciler.updateVirtualNodeWithChildren(virtualNode, targetHostParent, children)

	return virtualNode
end

function RobloxRenderer._updateFragmentVirtualNode(reconciler, virtualNode, newElement)
	reconciler.updateVirtualNodeWithChildren(virtualNode, virtualNode.hostParent, newElement.elements)

	return virtualNode
end

return RobloxRenderer
