#pragma once

#include <set>
#include <stdexcept>
#include <string>

namespace turbo
{

/**
 * @brief Abstract base class for geometry objects.
 *
 * All methods for geometry objects, other than the constructor, are essentially getters.
 * There is an implied assumption that geometry objects are immutable after construction.
 * This can be changed later if needed, but member function names should be updated to reflect getters, setters, etc.
 */
class Geometry
{
   public:
    //-----------------------------------------------------------------------//
    // Public Types
    //-----------------------------------------------------------------------//

    /**
     * @brief Type alias for boundary representation.
     */
    using Boundary = std::string;

    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//
    /**
     * @brief Constructor for Geometry.
     * @param boundaries Set of boundary names for the geometry.
     */
    //Geometry(std::set<Boundary> boundaries = {}) : boundaries_(boundaries) {}
    Geometry(const Boundary& i_low_boundary_name, const Boundary& i_high_boundary_name, const Boundary& j_low_boundary_name, const Boundary& j_high_boundary_name, const Boundary& k_low_boundary_name, const Boundary& k_high_boundary_name) :
        i_low_boundary_name_(i_low_boundary_name),
        i_high_boundary_name_(i_high_boundary_name),
        j_low_boundary_name_(j_low_boundary_name),
        j_high_boundary_name_(j_high_boundary_name),
        k_low_boundary_name_(k_low_boundary_name),
        k_high_boundary_name_(k_high_boundary_name)
    {}

    /**
     * @brief Virtual destructor for Geometry. Needed because this is an abstract base class.
     */
    virtual ~Geometry() = default;

    /**
     * @brief Get the set of boundaries for the geometry.
     * @return Set of boundary names.
     */
    const Boundary& GetILowBoundaryName(void) const noexcept { return i_low_boundary_name_; };
    const Boundary& GetIHighBoundaryName(void) const noexcept { return i_high_boundary_name_; };
    const Boundary& GetJLowBoundaryName(void) const noexcept { return j_low_boundary_name_; };
    const Boundary& GetJHighBoundaryName(void) const noexcept { return j_high_boundary_name_; };
    const Boundary& GetKLowBoundaryName(void) const noexcept { return k_low_boundary_name_; };
    const Boundary& GetKHighBoundaryName(void) const noexcept { return k_high_boundary_name_; };
    Boundary i_low_boundary_name_;
    Boundary i_high_boundary_name_;
    Boundary j_low_boundary_name_;
    Boundary j_high_boundary_name_;
    Boundary k_low_boundary_name_;
    Boundary k_high_boundary_name_;

    const std::set<Boundary> GetBoundaryNames() const noexcept { return {i_low_boundary_name_, i_high_boundary_name_, j_low_boundary_name_, j_high_boundary_name_, k_low_boundary_name_, k_high_boundary_name_}; }

   protected:
    //-----------------------------------------------------------------------//
    // Protected Member Data
    //-----------------------------------------------------------------------//

};

}  // namespace turbo
