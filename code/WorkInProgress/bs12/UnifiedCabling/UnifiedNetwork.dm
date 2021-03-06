// =
// = The Unified (-Type-Tree) Cable Network System
// = Written by Sukasa with assistance from Googolplexed
// =
// = Cleans up the type tree and reduces future code maintenance
// = Also makes it easy to add new cable & network types
// =

// Unified Cable Network System - Generic Network Class




//TODO: Instead of forcing machines to connect to only one Unified Network for each cable type, allow them to connect to multiple
//      networks if that network type allows it (or just always?)

/proc/CreateUnifiedNetwork(var/CableType)
	var/datum/UnifiedNetwork/NewNetwork = new()
	var/list/NetworkList = AllNetworks[CableType]

	if (!NetworkList)
		NetworkList = list( )
		AllNetworks[CableType] = NetworkList

	NetworkList += NewNetwork
	NewNetwork.NetworkNumber = NetworkList.len

	return NewNetwork


/datum/UnifiedNetwork
	var/datum/UnifiedNetworkController/Controller 	= null
	var/UnhandledExplosionDamage 					= 0
	var/NetworkNumber 								= 0
	var/list/Nodes 									= list( )
	var/list/Cables 								= list( )


/datum/UnifiedNetwork/proc/CutCable(var/obj/cable/blue/Cable)

	var/list/ConnectedCables = Cable.CableConnections(get_step(Cable, Cable.Direction1)) | Cable.CableConnections(get_step(Cable, Cable.Direction2))

	Controller.RemoveCable(Cable)

	if(!ConnectedCables.len)
		Cables -= Cable
		if (!Cables.len)
			for(var/obj/Node in Nodes)
				if(!Node.NetworkNumber)
					Controller.DetachNode(Node)
					Node.Networks[Cable.EquivalentCableType] = null
					Node.NetworkNumber[Cable.EquivalentCableType] = 0

			Controller.Finalize()
			del Controller
			del src

		return

	for(var/obj/C in Cables)
		C.NetworkNumber[Cable.EquivalentCableType] = 0
	for(var/obj/N in Nodes)
		N.NetworkNumber[Cable.EquivalentCableType] = 0

	Cable.loc = null
	Cables -= Cable
	if(Cable in ConnectedCables) CRASH("Cable connects to self.")

	PropagateNetwork(ConnectedCables[1], NetworkNumber)

	ConnectedCables -= ConnectedCables[1]

	for(var/obj/cable/blue/O in ConnectedCables)
		if(O.NetworkNumber[Cable.EquivalentCableType] == 0)

			var/datum/UnifiedNetwork/NewNetwork = CreateUnifiedNetwork(Cable.EquivalentCableType)
			NewNetwork.BuildFrom(O, Cable.NetworkControllerType)

			//PropagateNetwork(O, NewNetwork.NetworkNumber) [This is redundant after BuildFrom(). -Aryn]

			Controller.StartSplit(NewNetwork)

			for(var/obj/cable/blue/C in NewNetwork.Cables)
				Controller.RemoveCable(C)
				Cables -= C

			for(var/obj/Node in NewNetwork.Nodes)
				Nodes -= Node

			//BuildFrom() has already given the new network its boundaries,
			//so there's no need to add here. Instead, we should take away
			//anything now governed by the split network from this one's list.
			// -Aryn

			//for(var/obj/cable/blue/C in Cables)
			//	if(!C.NetworkNumber[Cable.EquivalentCableType])
			//		NewNetwork.AddCable(C)

			//for(var/obj/Node in Nodes)
			//	if(!Node.NetworkNumber[Cable.EquivalentCableType])
			//		NewNetwork.AddNode(Node,Cable)

			Controller.FinishSplit(NewNetwork)

			NewNetwork.Controller.Initialize()
	return


/datum/UnifiedNetwork/proc/BuildFrom(var/obj/cable/blue/Start, var/ControllerType = /datum/UnifiedNetworkController)
	var/list/Components = PropagateNetwork(Start, NetworkNumber)

	Controller = new ControllerType(src)

	for (var/obj/Component in Components)
		if (istype(Component, /obj/cabling))
			Cables += Component
			Controller.AddCable(Component)
		else
			Nodes += Component
			Controller.AttachNode(Component)

	Controller.Initialize()

	return


/datum/UnifiedNetwork/proc/PropagateNetwork(var/obj/cable/blue/Start, var/NewNetworkNumber)

	var/list/Connections   = list( )
	var/list/Possibilities = list(Start)

	while (Possibilities.len)
		for (var/obj/cable/blue/Cable in Possibilities.Copy())
			Possibilities |= Cable.AllConnections(get_step(Cable, Cable.Direction1))
			Possibilities |= Cable.AllConnections(get_step(Cable, Cable.Direction2))

		for (var/obj/Component in Possibilities.Copy())
			if (Component.NetworkNumber[Start.EquivalentCableType] != NewNetworkNumber)
				Component.NetworkNumber[Start.EquivalentCableType] = NewNetworkNumber
				Component.Networks[Start.EquivalentCableType] = src
				Connections += Component
				if (!istype(Component, /obj/cabling))
					Possibilities -= Component
			else
				Possibilities -= Component

#ifdef DEBUG
	world.log << "Created Unified Network (Type [Start.EquivalentCableType]) with [Connections.len] Components from [Start.x], [Start.y], [Start.z]"
#endif
	return Connections

/datum/UnifiedNetwork/proc/AddNode(var/obj/NewNode, var/obj/cable/blue/Cable)
	//world << "Adding [NewNode.name] to \[[Cable.EquivalentCableType]\] Network [NetworkNumber]"
	if(!istype(Cable,/obj/cabling))
		CRASH("Faulty second arg to AddNode: [Cable]")
	var/datum/UnifiedNetwork/CurrentNetwork = NewNode.Networks[Cable.EquivalentCableType]

	if (CurrentNetwork == src)
		return

	if (CurrentNetwork)
		CurrentNetwork.Controller.DetachNode(NewNode)

	NewNode.NetworkNumber[Cable.EquivalentCableType] = NetworkNumber
	NewNode.Networks[Cable.EquivalentCableType] = src

	if (CurrentNetwork)
		CurrentNetwork.Nodes -= NewNode

	Nodes += NewNode
	Controller.AttachNode(NewNode)
	return

/datum/UnifiedNetwork/proc/AddCable(var/obj/cable/blue/Cable)

	var/datum/UnifiedNetwork/CurrentNetwork = Cable.Networks[Cable.EquivalentCableType]
	if (CurrentNetwork == src)
		return

	if (CurrentNetwork)
		CurrentNetwork.Controller.RemoveCable(Cable)
	Cable.NetworkNumber[Cable.EquivalentCableType] = NetworkNumber
	Cable.Networks[Cable.EquivalentCableType] = src
	if (CurrentNetwork)
		CurrentNetwork.Cables -= Cable
	Cables += Cable
	Controller.AddCable(Cable)
	return

/datum/UnifiedNetwork/proc/CableBuilt(var/obj/cable/blue/Cable, var/list/Connections)
	var/list/MergeCables = list()

	for(var/obj/cable/blue/C in Connections)
		MergeCables += C

	for (var/obj/cable/blue/C in MergeCables)
		if (C.Networks[C.EquivalentCableType] != src)
			var/datum/UnifiedNetwork/OtherNetwork = C.Networks[C.EquivalentCableType]
			Controller.BeginMerge(OtherNetwork, 0)
			OtherNetwork.Controller.BeginMerge(src, 1)

			for (var/obj/cable/blue/CC in OtherNetwork.Cables)
				AddCable(CC)

			for (var/obj/M in OtherNetwork.Nodes)
				AddNode(M,Cable)

			Controller.FinishMerge()
			OtherNetwork.Controller.FinishMerge()
			OtherNetwork.Controller.Finalize()

			del OtherNetwork.Controller
			del OtherNetwork

	for(var/obj/Object in Connections - MergeCables)
		AddNode(Object,Cable)

	AddCable(Cable)
	Controller.AddCable(Cable)
	Cable.NetworkNumber[Cable.EquivalentCableType] = NetworkNumber
	Cable.Networks[Cable.EquivalentCableType] = src

	return
