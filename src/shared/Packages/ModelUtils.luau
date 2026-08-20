local ModelUtils = {}

function ModelUtils.GetModelBottom(model: Model)
	local boundingCFrame, boundingSize = model:GetBoundingBox()
	local bottomY = boundingCFrame.Position.Y - boundingSize.Y / 2
	return bottomY
end

function ModelUtils.AlignModelBottom(model: Model, targetPosition: Vector3)
	local boundingCFrame , _ = model:GetBoundingBox()
	local bottomY = ModelUtils.GetModelBottom(model)

	local delta = Vector3.new(
		targetPosition.X - boundingCFrame.Position.X,
		targetPosition.Y - bottomY,
		targetPosition.Z - boundingCFrame.Position.Z
	)
	model:PivotTo(model:GetPivot() + delta)
end

return ModelUtils
