--[[
	Reference renderer intended for use in tests as well as for documenting the
	minimum required interface for a Roact renderer.
]]
local Children = require(script.Parent.PropMarkers.Children)
local ElementKind = require(script.Parent.ElementKind)

local NoopRenderer = {}

function NoopRenderer.isHostObject(target)
	-- Attempting to use NoopRenderer to target a Roblox instance is almost
	-- certainly a mistake.
	return target == nil
end

function NoopRenderer.mountHostNode(reconciler, node)
end

function NoopRenderer.unmountHostNode(reconciler, node)
end

function NoopRenderer.updateHostNode(reconciler, node, newElement)
	return node
end

function NoopRenderer.mountVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement
	local kind = ElementKind.of(element)

	if kind == ElementKind.Host then
		NoopRenderer.mountHostNode(reconciler, virtualNode)
	elseif kind == ElementKind.Function then
		NoopRenderer.mountFunctionVirtualNode(reconciler, virtualNode)
	elseif kind == ElementKind.Stateful then
		element.component:__mount(reconciler, virtualNode)
	elseif kind == ElementKind.Portal then
		NoopRenderer.mountPortalVirtualNode(reconciler, virtualNode)
	elseif kind == ElementKind.Fragment then
		NoopRenderer.mountFragmentVirtualNode(reconciler, virtualNode)
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end
end

function NoopRenderer.mountFunctionVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement

	local children = element.component(element.props)

	reconciler.updateVirtualNodeWithRenderResult(virtualNode, virtualNode.hostParent, children)
end

function NoopRenderer.mountPortalVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement

	local targetHostParent = element.props.target
	local children = element.props[Children]

	assert(NoopRenderer.isHostObject(targetHostParent), "Expected target to be host object")

	reconciler.updateVirtualNodeWithChildren(virtualNode, targetHostParent, children)
end

function NoopRenderer.mountFragmentVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement
	local children = element.elements

	reconciler.updateVirtualNodeWithChildren(virtualNode, virtualNode.hostParent, children)
end

function NoopRenderer.unmountVirtualNode(reconciler, virtualNode)
	local kind = ElementKind.of(virtualNode.currentElement)

	if kind == ElementKind.Host then
		NoopRenderer.unmountHostNode(reconciler, virtualNode)
	elseif kind == ElementKind.Function then
		for _, childNode in pairs(virtualNode.children) do
			reconciler.unmountVirtualNode(childNode)
		end
	elseif kind == ElementKind.Stateful then
		virtualNode.instance:__unmount()
	elseif kind == ElementKind.Portal then
		for _, childNode in pairs(virtualNode.children) do
			reconciler.unmountVirtualNode(childNode)
		end
	elseif kind == ElementKind.Fragment then
		for _, childNode in pairs(virtualNode.children) do
			reconciler.unmountVirtualNode(childNode)
		end
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end
end

function NoopRenderer.updateVirtualNode(reconciler, virtualNode, newElement, newState)
	local kind = ElementKind.of(newElement)

	local shouldContinueUpdate = true

	if kind == ElementKind.Host then
		virtualNode = NoopRenderer.updateHostNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Function then
		virtualNode = NoopRenderer.updateFunctionVirtualNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Stateful then
		shouldContinueUpdate = virtualNode.instance:__update(newElement, newState)
	elseif kind == ElementKind.Portal then
		virtualNode = NoopRenderer.updatePortalVirtualNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Fragment then
		virtualNode = NoopRenderer.updateFragmentVirtualNode(reconciler, virtualNode, newElement)
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end

	if shouldContinueUpdate then
		virtualNode.currentElement = newElement
	end

	return virtualNode
end

function NoopRenderer.updateFunctionVirtualNode(reconciler, virtualNode, newElement)
	local children = newElement.component(newElement.props)

	reconciler.updateVirtualNodeWithRenderResult(virtualNode, virtualNode.hostParent, children)

	return virtualNode
end

function NoopRenderer.updatePortalVirtualNode(reconciler, virtualNode, newElement)
	local oldElement = virtualNode.currentElement
	local oldTargetHostParent = oldElement.props.target

	local targetHostParent = newElement.props.target

	assert(NoopRenderer.isHostObject(targetHostParent), "Expected target to be host object")

	if targetHostParent ~= oldTargetHostParent then
		return reconciler.replaceVirtualNode(virtualNode, newElement)
	end

	local children = newElement.props[Children]

	reconciler.updateVirtualNodeWithChildren(virtualNode, targetHostParent, children)

	return virtualNode
end

function NoopRenderer.updateFragmentVirtualNode(reconciler, virtualNode, newElement)
	reconciler.updateVirtualNodeWithChildren(virtualNode, virtualNode.hostParent, newElement.elements)

	return virtualNode
end

return NoopRenderer