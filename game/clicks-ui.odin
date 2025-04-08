package game

GenericAction :: proc()
OrderAction :: struct {
	unitId: int,
	order: Order
}
SelectAction :: ^GameUnit

ClickAction :: union {
	GenericAction,
	OrderAction,
	SelectAction
}

@(private)
clickQueue: ClickAction

postponeClick :: proc(action: ClickAction) {
	clickQueue = action
}
postponeGenericAction :: proc(action: proc()) {
	postponeClick(GenericAction(action))
}

flushClickQueue :: proc() {
	switch action in clickQueue {
		case GenericAction:
			#assert(type_of(action) == GenericAction)
			action()
		case OrderAction:
			#assert(type_of(action) == OrderAction)
			createOrder(action.unitId, action.order)
		case SelectAction:
			#assert(type_of(action) == SelectAction)
			selectedUnit = action
	}

	clickQueue = nil
}
