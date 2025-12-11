#include <gtest/gtest.h>

#include <AMReX.H>
#include <AMReX_MultiFab.H>

#include <memory>
#include <string>
#include <stdexcept>
#include <algorithm>

#include "cartesian_geometry.h" // Replace with cartesian_geometry.h when it is seperated out of geometry.h
#include "cartesian_grid.h"
#include "cartesian_domain.h"

#include "amrex_test_environment.h"

using namespace turbo;

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());


class CartesianDomainTest : public ::testing::Test {
protected:
    double x_min, x_max, y_min, y_max, z_min, z_max;
    std::size_t n_cell_x, n_cell_y, n_cell_z;

    void SetUp() override {
        x_min = 0.0;
        x_max = 1.0;
        y_min = 0.0;
        y_max = 1.0;
        z_min = 0.0;
        z_max = 1.0;

        // Default grid size for most tests
        n_cell_x = 8;
        n_cell_y = 16;
        n_cell_z = 4;
    }
};

TEST_F(CartesianDomainTest, Constructor) {
    
    CartesianDomain cartesian_domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);

}

TEST_F(CartesianDomainTest, Getters) {
    
    CartesianDomain cartesian_domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);

    std::shared_ptr<CartesianGeometry> geometry = cartesian_domain.GetGeometry();
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

    std::shared_ptr<CartesianGrid> grid = cartesian_domain.GetGrid();
    EXPECT_NE(grid, nullptr);
    EXPECT_EQ(grid->NCellI(), n_cell_x);
    EXPECT_EQ(grid->NCellJ(), n_cell_y);
    EXPECT_EQ(grid->NCellK(), n_cell_z);

    auto fields = cartesian_domain.GetFields();
    EXPECT_TRUE(fields.empty());

}

TEST_F(CartesianDomainTest, CreateField) {
    
    CartesianDomain cartesian_domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);
    
    auto fields = cartesian_domain.GetFields();
    EXPECT_TRUE(fields.empty());

    const std::string field_name = "test_field";
    const std::size_t n_ghost = 2;
    const std::size_t n_component = 1;
    std::shared_ptr<Field> field = cartesian_domain.CreateField(field_name, FieldGridStagger::CellCentered, n_component, n_ghost);

    EXPECT_EQ(fields.size(), 1);

    EXPECT_TRUE(cartesian_domain.HasField(field_name));

    // Verify the field is included in the return value from GetFields
    EXPECT_TRUE(std::ranges::any_of(fields, [field_name](const std::shared_ptr<Field>& field) {
        return field->name == field_name;
    }));

    EXPECT_EQ(cartesian_domain.GetField(field_name), field);

    // Attempting to create a field with the same name should throw an exception
    EXPECT_THROW(cartesian_domain.CreateField(field_name, FieldGridStagger::CellCentered, n_component, n_ghost), std::invalid_argument);

}


//TEST_F(CartesianDomainTest, Initialize_Multifabs) {
//
//    Domain domain(grid);
//
//    domain.InitializeScalarMultiFabs([](double x, double y, double z) {
//        return 1.23;
//    });
//
//    for (const std::shared_ptr<amrex::MultiFab>& mf : domain.scalar_multifabs) {
//        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
//            auto arr = mf->array(mfi);
//            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
//                EXPECT_EQ(arr(i, j, k), 1.23);
//            });
//        }
//    }
//
//    domain.InitializeVectorMultiFabs([](double x, double y, double z) {
//        return std::array<double, 3>{1.0, 2.0, 3.0};
//    });
//
//    for (const std::shared_ptr<amrex::MultiFab>& mf : domain.vector_multifabs) {
//        for (amrex::MFIter mfi(*mf); mfi.isValid(); ++mfi) {
//            auto arr = mf->array(mfi);
//            amrex::ParallelFor(mfi.validbox(), [=,this] AMREX_GPU_DEVICE(int i, int j, int k) {
//                EXPECT_EQ(arr(i, j, k, 0), 1.0);
//                EXPECT_EQ(arr(i, j, k, 1), 2.0);
//                EXPECT_EQ(arr(i, j, k, 2), 3.0);
//            });
//        }
//    }
//}


TEST_F(CartesianDomainTest, WriteHDF5) {

    CartesianDomain cartesian_domain(x_min, x_max,
                                     y_min, y_max,
                                     z_min, z_max,
                                     n_cell_x,
                                     n_cell_y,
                                     n_cell_z);
    

    //cartesian_domain.InitializeScalarMultiFabs([](double x, double y, double z) {
    //    return x;
    //});

    //cartesian_domain.InitializeVectorMultiFabs([](double x, double y, double z) {
    //    return std::array<double, 3>{x, y, z};
    //});

    cartesian_domain.WriteHDF5("Test_Output_Domain_WriteHDF5.h5");
}