#pragma once

#include <cstddef>
#include <map>
#include <memory>
#include <ranges>
#include <stdexcept>
#include <string>

#include "field.h"
#include "geometry.h"
#include "grid.h"

namespace turbo 
{

//enum class Boundary
//{
//   ILow,
//   IHigh,
//   JLow,
//   JHigh,
//   KLow,
//   KHigh
//};

enum class BoundaryCondition
{
  None,
  Periodic,
  Dirichlet,
  Neumann,
};

class Domain
{
   public:
    //-----------------------------------------------------------------------//
    // Public Member Functions
    //-----------------------------------------------------------------------//

    /**
     * @brief Constructor for Domain.
     * @param grid Shared pointer to the Grid associated with the domain.
     */
    Domain(const std::shared_ptr<Grid>& grid);

    /**
     * @brief Virtual destructor for Domain.
     */
    virtual ~Domain() = default;

    /**
     * @brief Get the geometry associated with the domain.
     * @return Shared pointer to the Geometry.
     */
    std::shared_ptr<Geometry> GetGeometry()
        const noexcept;  // TODO: Maybe dont need this function if we can always get the geometry from the grid?
    // Maybe have grid not be commited to supporting geometry at some point in the future? That way some grids could not
    // tied to a geometry object?

    /**
     * @brief Get the grid associated with the domain.
     * @return Shared pointer to the Grid.
     */
    std::shared_ptr<Grid> GetGrid() const noexcept;

    /**
     * @brief Get a view of all fields in the domain's field container.
     * @return A range view of shared pointers to Fields.
     */
    // Have to inline the definition in the header file so that the return type can be deduced properly by auto
    std::ranges::view auto GetFields() const noexcept { return std::views::values(field_container_); }

    /**
     * @brief Create a field to the domain's field container.
     * @param name Name of the field.
     * @param stagger Field grid staggering type.
     * @param n_component Number of components (e.g., 1 for scalar fields).
     * @param n_ghost Number of ghost cells.
     * @return Shared pointer to the newly created field.
     * @throws std::invalid_argument if invalid input (name already exists in container, invalid number of components or
     * ghost cells, invalid stagger type, etc.).
     * @throws std::logic_error if the field cannot be inserted into the container given valid input.
     */
    std::shared_ptr<Field> CreateField(const Field::NameType& field_name, const FieldGridStagger stagger,
                                       const std::size_t n_component, const std::size_t n_ghost);

    /**
     * @brief Get a field by name from the domain's field container.
     * @param name Name of the field to retrieve.
     * @return Shared pointer to the Field.
     * @throws std::invalid_argument if the field does not exist.
     */
    std::shared_ptr<Field> GetField(const Field::NameType& field_name) const;

    /**
     * @brief Check if a field with the given name exists in the domain's field container.
     * @param field_name Name of the field to check.
     * @return true if the field exists, false otherwise.
     */
    bool HasField(const Field::NameType& field_name) const;

    /**
     * @brief Write the domain data to an HDF5 file.
     * @param filename Name of the HDF5 file to write.
     */
    void WriteHDF5(const std::string& filename) const;

    /**
     * @brief Write the domain data to an HDF5 file.
     * @param file_id HDF5 file identifier.
     */
    void WriteHDF5(const hid_t file_id) const;

    void SetILowBoundaryCondition(const BoundaryCondition boundary_condition) {
      SetBoundaryCondition(GetGeometry()->i_low_boundary_name_, boundary_condition);
    };
    void SetIHighBoundaryCondition(const BoundaryCondition boundary_condition) {
      SetBoundaryCondition(GetGeometry()->i_high_boundary_name_, boundary_condition);
    };
    void SetJLowBoundaryCondition(const BoundaryCondition boundary_condition) {
      SetBoundaryCondition(GetGeometry()->j_low_boundary_name_, boundary_condition);
    };
    void SetJHighBoundaryCondition(const BoundaryCondition boundary_condition) {
      SetBoundaryCondition(GetGeometry()->j_high_boundary_name_, boundary_condition);
    };
    void SetKLowBoundaryCondition(const BoundaryCondition boundary_condition) {
      SetBoundaryCondition(GetGeometry()->k_low_boundary_name_, boundary_condition);
    };
    void SetKHighBoundaryCondition(const BoundaryCondition boundary_condition) {
      SetBoundaryCondition(GetGeometry()->k_high_boundary_name_, boundary_condition);
    };

    /**
     * @brief Set the boundary condition for a given boundary name.
     * @param boundary_name Name of the boundary.
     * @param boundary_condition Boundary condition to set.
     * @throws std::invalid_argument if the boundary name is invalid.
     */
    void SetBoundaryCondition(const Geometry::Boundary& boundary_name, const BoundaryCondition boundary_condition) {
      if (!boundary_conditions_.contains(boundary_name)) {
          throw std::invalid_argument("Invalid boundary name passed to SetBoundaryCondition: " + boundary_name);
      }
         boundary_conditions_[boundary_name] = boundary_condition;
    };

 protected:

   protected:
    /**
     * @brief Shared pointer to the grid associated with the domain.
     */
    const std::shared_ptr<Grid> grid_;

    /**
     * @brief Container for the fields defined on the domain.
     */
    std::map<Field::NameType, std::shared_ptr<Field>> field_container_;

    /**
     * @brief Map to store boundary conditions for each boundary name defined in the geometry.
     */
    std::map<Geometry::Boundary, BoundaryCondition> boundary_conditions_;
};

}  // namespace turbo
