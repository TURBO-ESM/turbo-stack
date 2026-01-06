#include <gtest/gtest.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <memory>
#include <string>
#include <stdexcept>
#include <algorithm>

#include "cartesian_geometry.h" 
#include "cartesian_grid.h"
#include "cartesian_domain.h"

#include "amrex_test_environment.h"

using namespace turbo;

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());


class CartesianDomainTest : public ::testing::Test {
protected:
    double x_min, x_max, y_min, y_max, z_min, z_max;
    std::size_t n_cell_x, n_cell_y, n_cell_z;
    std::unique_ptr<CartesianDomain> cartesian_domain;

    void SetUp() override {
        x_min = 0.0;
        x_max = 1.0;
        y_min = 0.0;
        y_max = 1.0;
        z_min = 0.0;
        z_max = 1.0;

        // Default grid size for most tests
        n_cell_x = 2;
        n_cell_y = 3;
        n_cell_z = 4;

        cartesian_domain = std::make_unique<CartesianDomain>(x_min, x_max,
                                           y_min, y_max,
                                           z_min, z_max,
                                           n_cell_x,
                                           n_cell_y,
                                           n_cell_z);
    }
};

TEST(CartesianDomainConstructorTest, Constructor) {

    double x_min = 0.0;
    double x_max = 1.0;
    double y_min = 0.0;
    double y_max = 1.0;
    double z_min = 0.0;
    double z_max = 1.0;

    std::size_t n_cell_x = 2;
    std::size_t n_cell_y = 4;
    std::size_t n_cell_z = 8;
    
    CartesianDomain cartesian_domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);

    // Expect constructor to throw with invalid input

    // Invalid domain extents (min >= max)
    EXPECT_THROW(CartesianDomain(1.0, -1.0,
                                 y_min, y_max,
                                 z_min, z_max,
                                 n_cell_x,
                                 n_cell_y,
                                 n_cell_z), std::invalid_argument);

    EXPECT_THROW(CartesianDomain(x_min, x_max,
                                 y_min, y_max,
                                 1.0, -1.0,
                                 n_cell_x,
                                 n_cell_y,
                                 n_cell_z), std::invalid_argument);

    EXPECT_THROW(CartesianDomain(x_min, x_max,
                                 1.0, -1.0,
                                 z_min, z_max,
                                 n_cell_x,
                                 n_cell_y,
                                 n_cell_z), std::invalid_argument);

    // Invalid number of cells (zero)
    EXPECT_THROW(CartesianDomain(x_min, x_max,
                                 y_min, y_max,
                                 z_min, z_max,
                                 0,
                                 n_cell_y,
                                 n_cell_z), std::invalid_argument);

    EXPECT_THROW(CartesianDomain(x_min, x_max,
                                 y_min, y_max,
                                 z_min, z_max,
                                 n_cell_x,
                                 0,
                                 n_cell_z), std::invalid_argument);

    EXPECT_THROW(CartesianDomain(x_min, x_max,
                                 y_min, y_max,
                                 z_min, z_max,
                                 n_cell_x,
                                 n_cell_y,
                                 0), std::invalid_argument);

}

TEST_F(CartesianDomainTest, Getters_and_Initial_State) {

    std::shared_ptr<CartesianGeometry> geometry = cartesian_domain->GetGeometry();
    EXPECT_NE(geometry, nullptr);
    EXPECT_DOUBLE_EQ(geometry->XMin(), x_min);
    EXPECT_DOUBLE_EQ(geometry->XMax(), x_max);
    EXPECT_DOUBLE_EQ(geometry->YMin(), y_min);
    EXPECT_DOUBLE_EQ(geometry->YMax(), y_max);
    EXPECT_DOUBLE_EQ(geometry->ZMin(), z_min);
    EXPECT_DOUBLE_EQ(geometry->ZMax(), z_max);
    EXPECT_DOUBLE_EQ(geometry->LX(), x_max - x_min);
    EXPECT_DOUBLE_EQ(geometry->LY(), y_max - y_min);
    EXPECT_DOUBLE_EQ(geometry->LZ(), z_max - z_min);

    std::shared_ptr<CartesianGrid> grid = cartesian_domain->GetGrid();
    EXPECT_NE(grid, nullptr);
    EXPECT_EQ(grid->NCellI(), n_cell_x);
    EXPECT_EQ(grid->NCellJ(), n_cell_y);
    EXPECT_EQ(grid->NCellK(), n_cell_z);

    auto fields = cartesian_domain->GetFields();
    EXPECT_TRUE(fields.empty());

}

TEST_F(CartesianDomainTest, Create_and_Get_Field) {

    const std::string field_name = "test_field";
    const std::size_t n_ghost = 2;
    const std::size_t n_component = 1;
    std::shared_ptr<Field> field = cartesian_domain->CreateField(field_name, FieldGridStagger::CellCentered, n_component, n_ghost);

    EXPECT_TRUE(cartesian_domain->HasField(field_name));

    // Verify the field getter returns the field that was created
    EXPECT_EQ(cartesian_domain->GetField(field_name), field);

    // Attempting to create a field with the same name as existing field, this should throw an exception
    EXPECT_THROW(cartesian_domain->CreateField(field_name, FieldGridStagger::CellCentered, n_component, n_ghost), std::invalid_argument);
}

TEST_F(CartesianDomainTest, FieldView) {
    
    auto fields = cartesian_domain->GetFields();
    
    EXPECT_TRUE(fields.empty());

    const std::size_t n_ghost = 2;
    const std::size_t n_component = 1;

    cartesian_domain->CreateField("test_field_1", FieldGridStagger::CellCentered, n_component, n_ghost);
    EXPECT_EQ(fields.size(), 1);

    cartesian_domain->CreateField("test_field_2", FieldGridStagger::CellCentered, n_component, n_ghost);
    EXPECT_EQ(fields.size(), 2);
}

TEST_F(CartesianDomainTest, WriteHDF5) {
    const std::string field_name = "test_field";
    const std::size_t n_ghost = 2;
    const std::size_t n_component = 1;
    cartesian_domain->CreateField(field_name, FieldGridStagger::CellCentered, n_component, n_ghost);

    for (auto& field : cartesian_domain->GetFields()) {
        //field->Initialize([](double x, double y, double z) {
        //    return std::vector<turbo::Field::ValueType>{x + y + z};
        //});

        amrex::MultiFab& mf = *(field->multifab);
        for (amrex::MFIter mfi(mf); mfi.isValid(); ++mfi) {
            const amrex::Array4<amrex::Real>& array = mf.array(mfi);
            amrex::ParallelFor(mfi.validbox(), [=] AMREX_GPU_DEVICE(int i, int j, int k) {
                const turbo::Grid::Point grid_point = field->GetGridPoint(i, j, k); 
                array(i, j, k) = grid_point.x; // Example: initialize scalar field with x-coordinate
            });
        }

    }

    cartesian_domain->WriteHDF5("Test_Output_CartesianDomain_WriteHDF5.h5");
}