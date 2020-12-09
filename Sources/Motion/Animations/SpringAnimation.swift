//
//  SpringAnimation.swift
//
//
//  Created by Adam Bell on 7/12/20.
//

import Combine
import QuartzCore
import simd

/**
 This class provides the ability to animate `Value` using a physically-modeled spring.

 `value` will be animated towards `toValue` (optionally seeded with `velocity) and depending on how the spring is configured, may bounce around the endpoint.

 Springs can be configured as underdamped, overdamped, or critically-damped, depending on the constants supplied.

 Stopping a spring via `stop` allows for redirecting the spring any way you'd like (perhaps in a different direction or velocity).

 ```
 let springAnimation = SpringAnimation<CGRect>(initialValue: .zero)
 springAnimation.toValue = CGRect(x: 0.0, y: 0.0, width: 100.0, height: 100.0)
 springAnimation.configure(
 ```
 */
public final class SpringAnimation<Value: SIMDRepresentable>: ValueAnimation<Value> {

    public override var velocity: Value {
         get {
            // We override velocity to be negative, since that's typically easier to reason about (i.e. touch velocity).
             return Value(-_velocity)
         }
         set {
            // See getter.
             self._velocity = -newValue.simdRepresentation()
         }
     }

    internal var spring: SpringFunction<Value.SIMDType>

    public var damping: Value.SIMDType.SIMDType.Scalar {
        return spring.damping
    }

    public var stiffness: Value.SIMDType.SIMDType.Scalar {
        return spring.stiffness
    }

    public var response: Value.SIMDType.SIMDType.Scalar {
        return spring.response
    }

    public var dampingRatio: Value.SIMDType.SIMDType.Scalar {
        return spring.dampingRatio
    }

    public var clampingRange: ClosedRange<Value>? {
        get {
            if let clampingRange = _clampingRange {
                return Value(clampingRange.lowerBound)...Value(clampingRange.upperBound)
            } else {
                return nil
            }
        }
        set {
            if let newValue = newValue {
                self._clampingRange = newValue.lowerBound.simdRepresentation()...newValue.upperBound.simdRepresentation()
            } else {
                self._clampingRange = nil
            }
        }
    }
    internal var _clampingRange: ClosedRange<Value.SIMDType>? = nil

    public init(initialValue: Value = .zero) {
        self.spring = SpringFunction()
        super.init()
        self.value = initialValue
    }

    public convenience init(initialValue: Value = .zero, response: Value.SIMDType.SIMDType.Scalar, dampingRatio: Value.SIMDType.SIMDType.Scalar) {
        self.init(initialValue: initialValue)
        configure(response: response, dampingRatio: dampingRatio)
    }

    public convenience init(initialValue: Value = .zero, stiffness: Value.SIMDType.SIMDType.Scalar, damping: Value.SIMDType.SIMDType.Scalar) {
        self.init(initialValue: initialValue)
        configure(stiffness: stiffness, damping: damping)
    }

    public func configure(stiffness: Value.SIMDType.SIMDType.Scalar, damping: Value.SIMDType.SIMDType.Scalar) {
        spring.configure(stiffness: response, damping: damping)
    }

    public func configure(response: Value.SIMDType.SIMDType.Scalar, dampingRatio: Value.SIMDType.SIMDType.Scalar) {
        spring.configure(response: response, dampingRatio: dampingRatio)
    }

    public override func hasResolved() -> Bool {
        return hasResolved(velocity: &_velocity, value: &_value)
    }

    internal func hasResolved(velocity: inout Value.SIMDType, value: inout Value.SIMDType) -> Bool {
        return velocity.approximatelyEqual(to: .zero) && value.approximatelyEqual(to: _toValue)
    }

    public override func stop(resolveImmediately: Bool = false, postValueChanged: Bool = false) {
        super.stop(resolveImmediately: resolveImmediately, postValueChanged: postValueChanged)
        self.velocity = .zero
    }

    // MARK: - DisplayLinkObserver

    public override func tick(_ dt: CFTimeInterval) {
        tickOptimized(Value.SIMDType.SIMDType.Scalar(dt), spring: &spring, value: &_value, toValue: &_toValue, velocity: &_velocity, clampingRange: &_clampingRange)

        _valueChanged?(value)

        if hasResolved() {
            stop()

            self.value = toValue
            _valueChanged?(value)

            completion?()
        }
    }

    /*
     This looks hideous, yes, but it forces the compiler to generate specialized versions (where the type is hardcoded) of the spring evaluation function.
     Normally this would be specialized, but because of the dynamic dispatch of -tick:, it fails to specialize.
     By specializing manually, we forcefully generate implementations of this method hardcoded for each SIMD type specified. Whilst this does incur a codesize penalty, this results in a performance boost of more than **+100%**.
     */
    @_specialize(kind: partial, where SIMDType == SIMD2<Float>)
    @_specialize(kind: partial, where SIMDType == SIMD2<Double>)
    @_specialize(kind: partial, where SIMDType == SIMD3<Float>)
    @_specialize(kind: partial, where SIMDType == SIMD3<Double>)
    @_specialize(kind: partial, where SIMDType == SIMD4<Float>)
    @_specialize(kind: partial, where SIMDType == SIMD4<Double>)
    @_specialize(kind: partial, where SIMDType == SIMD8<Float>)
    @_specialize(kind: partial, where SIMDType == SIMD8<Double>)
    @_specialize(kind: partial, where SIMDType == SIMD16<Float>)
    @_specialize(kind: partial, where SIMDType == SIMD16<Double>)
    @_specialize(kind: partial, where SIMDType == SIMD32<Float>)
    @_specialize(kind: partial, where SIMDType == SIMD32<Double>)
    @_specialize(kind: partial, where SIMDType == SIMD64<Float>)
    @_specialize(kind: partial, where SIMDType == SIMD64<Double>)
    internal func tickOptimized<SIMDType: SupportedSIMD>(_ dt: SIMDType.SIMDType.Scalar, spring: inout SpringFunction<SIMDType>, value: inout SIMDType, toValue: inout SIMDType, velocity: inout SIMDType, clampingRange: inout ClosedRange<SIMDType>?) {
        let x0 = toValue - value

        let x = spring.solve(dt: dt, x0: x0, velocity: &velocity)

        value = toValue - x

        if let clampingRange = clampingRange {
            value.clamp(lowerBound: clampingRange.lowerBound, upperBound: clampingRange.upperBound)
        }
    }
    
}
