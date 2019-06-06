local Type = require(script.Parent.Type)
local Symbol = require(script.Parent.Symbol)

local function noop()
	return nil
end

local ElementUtils = {}

--[[
	A signal value indicating that a child should use its parent's key, because
	it has no key of its own.

	This occurs when you return only one element from a function component or
	stateful render function.
]]
ElementUtils.UseParentKey = Symbol.named("UseParentKey")

local function tableIterator(elements)
	local state = {
		elements = elements,
		returnTable = nil,
		previous = nil,
	}
	local keyStack = {}
	local keyStackIndex = 0

	local pushState
	local popState

	local function nextElement(state, previous)
		local nextKey, nextValue = next(state.elements, state.previous)

		if nextKey == nil then
			if state.returnTable == nil then
				return nil
			else
				popState()
				return nextElement(state)
			end
		end

		if Type.of(nextValue) == Type.Fragment then
			pushState(nextKey, nextValue)
			return nextElement(state)
		end

		state.previous = nextKey
		
		if keyStackIndex == 0 then
			return nextKey, nextValue
		else
			return keyStack, nextValue
		end
	end

	function pushState(key, value)
		keyStackIndex = keyStackIndex + 1
		keyStack[keyStackIndex] = key

		state.returnTable = {
			elements = state.elements,
			returnTable = state.returnTable,
			previous = key,
		}
		state.elements = value.elements
		state.previous = nil
	end

	function popState()
		keyStack[keyStackIndex] = nil
		keyStackIndex = keyStackIndex - 1

		state.elements = state.returnTable.elements
		state.previous = state.returnTable.previous
		state.returnTable = state.returnTable.returnTable
	end

	return nextElement, state
end
--[[
	Returns an iterator over the children of an element.
	`elementOrElements` may be one of:
	* a boolean
	* nil
	* a single element
	* a fragment
	* a table of elements

	If `elementOrElements` is a boolean or nil, this will return an iterator with
	zero elements.

	If `elementOrElements` is a single element, this will return an iterator with
	one element: a tuple where the first value is ElementUtils.UseParentKey, and
	the second is the value of `elementOrElements`.

	If `elementOrElements` is a fragment or a table, this will return an iterator
	over all the elements of the array.

	If `elementOrElements` is none of the above, this function will throw.
]]
function ElementUtils.iterateElements(elementOrElements)
	local richType = Type.of(elementOrElements)

	if richType == Type.Fragment then
		return pairs(elementOrElements.elements)
	end

	-- Single child
	if richType == Type.Element then
		local called = false

		return function()
			if called then
				return nil
			else
				called = true
				return ElementUtils.UseParentKey, elementOrElements
			end
		end
	end

	local regularType = typeof(elementOrElements)

	if elementOrElements == nil or regularType == "boolean" then
		return noop
	end

	if regularType == "table" then
		return tableIterator(elementOrElements)
	end

	error("Invalid elements")
end

--[[
	Gets the child corresponding to a given key, respecting Roact's rules for
	children. Specifically:
	* If `elements` is nil or a boolean, this will return `nil`, regardless of
		the key given.
	* If `elements` is a single element, this will return `nil`, unless the key
		is ElementUtils.UseParentKey.
	* If `elements` is a table of elements, this will return `elements[key]`.
]]
function ElementUtils.getElementByKey(elements, hostKey)
	if elements == nil or typeof(elements) == "boolean" then
		return nil
	end

	if Type.of(elements) == Type.Element then
		if hostKey == ElementUtils.UseParentKey then
			return elements
		end

		return nil
	end

	if Type.of(elements) == Type.Fragment then
		return elements.elements[hostKey]
	end

	if typeof(elements) == "table" then
		if type(hostKey) == "table" then
			local element = elements

			for i=1, #hostKey do
				element = ElementUtils.getElementByKey(element, hostKey[i])
			end

			return element
		else
			return elements[hostKey]
		end
	end

	error("Invalid elements")
end

return ElementUtils