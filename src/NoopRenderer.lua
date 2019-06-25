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

function NoopRenderer.mountVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement
	local kind = ElementKind.of(element)

	if kind == ElementKind.Host then
		NoopRenderer._mountHostNode(reconciler, virtualNode)
	elseif kind == ElementKind.Function then
		NoopRenderer._mountFunctionVirtualNode(reconciler, virtualNode)
	elseif kind == ElementKind.Stateful then
		element.component:__mount(reconciler, virtualNode)
	elseif kind == ElementKind.Portal then
		NoopRenderer._mountPortalVirtualNode(reconciler, virtualNode)
	elseif kind == ElementKind.Fragment then
		NoopRenderer._mountFragmentVirtualNode(reconciler, virtualNode)
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end
end

function NoopRenderer._mountHostNode(reconciler, node)
end

function NoopRenderer._mountFunctionVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement

	local children = element.component(element.props)

	reconciler.updateVirtualNodeWithRenderResult(virtualNode, virtualNode.hostParent, children)
end

function NoopRenderer._mountPortalVirtualNode(reconciler, virtualNode)
end

function NoopRenderer._mountFragmentVirtualNode(reconciler, virtualNode)
	local element = virtualNode.currentElement
	local children = element.elements

	reconciler.updateVirtualNodeWithChildren(virtualNode, virtualNode.hostParent, children)
end

function NoopRenderer.unmountVirtualNode(virtualNode)
	local kind = ElementKind.of(virtualNode.currentElement)

	if kind == ElementKind.Host then
		NoopRenderer._unmountHostNode(virtualNode)
	elseif kind == ElementKind.Function then
		for _, childNode in pairs(virtualNode.children) do
			NoopRenderer.unmountVirtualNode(childNode)
		end
	elseif kind == ElementKind.Stateful then
		virtualNode.instance:__unmount()
	elseif kind == ElementKind.Portal then
		for _, childNode in pairs(virtualNode.children) do
			NoopRenderer.unmountVirtualNode(childNode)
		end
	elseif kind == ElementKind.Fragment then
		for _, childNode in pairs(virtualNode.children) do
			NoopRenderer.unmountVirtualNode(childNode)
		end
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end
end

function NoopRenderer._unmountHostNode(node)
end

function NoopRenderer.updateVirtualNode(reconciler, virtualNode, newElement, newState)
	local kind = ElementKind.of(newElement)

	local shouldContinueUpdate = true

	if kind == ElementKind.Host then
		virtualNode = NoopRenderer._updateHostNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Function then
		virtualNode = NoopRenderer._updateFunctionVirtualNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Stateful then
		shouldContinueUpdate = virtualNode.instance:__update(newElement, newState)
	elseif kind == ElementKind.Portal then
		virtualNode = NoopRenderer._updatePortalVirtualNode(reconciler, virtualNode, newElement)
	elseif kind == ElementKind.Fragment then
		virtualNode = NoopRenderer._updateFragmentVirtualNode(reconciler, virtualNode, newElement)
	else
		error(("Unknown ElementKind %q"):format(tostring(kind), 2))
	end

	if shouldContinueUpdate then
		virtualNode.currentElement = newElement
	end

	return virtualNode
end

function NoopRenderer._updateHostNode(reconciler, node, newElement)
	return node
end

function NoopRenderer._updateFunctionVirtualNode(reconciler, virtualNode, newElement)
	return virtualNode
end

function NoopRenderer._updatePortalVirtualNode(reconciler, virtualNode, newElement)
	return virtualNode
end

function NoopRenderer._updateFragmentVirtualNode(reconciler, virtualNode, newElement)
	return virtualNode
end

return NoopRenderer