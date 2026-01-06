#include "field.h"

#include <AMReX.H>
#include <AMReX_MultiFab.H>
#include <gtest/gtest.h>

#include <memory>
#include <stdexcept>
#include <string>

#include "amrex_test_environment.h"
#include "cartesian_grid.h"
#include "geometry.h"

using namespace turbo;

::testing::Environment* const amrex_env = ::testing::AddGlobalTestEnvironment(new AmrexEnvironment());

//---------------------------------------------------------------------------//
// Define a test fixture for field tests
//---------------------------------------------------------------------------//

class FieldTest : public ::testing::Test
{
   protected:
    void SetUp() override
    {
        double x_min         = 0.0;
        double x_max         = 1.0;
        double y_min         = 0.0;
        double y_max         = 1.0;
        double z_min         = 0.0;
        double z_max         = 1.0;
        geometry             = std::make_shared<CartesianGeometry>(x_min, x_max, y_min, y_max, z_min, z_max);

        std::size_t n_cell_x = 2;
        std::size_t n_cell_y = 3;
        std::size_t n_cell_z = 4;
        grid                 = std::make_shared<CartesianGrid>(geometry, n_cell_x, n_cell_y, n_cell_z);
    }

    std::shared_ptr<CartesianGeometry> geometry;
    std::shared_ptr<CartesianGrid> grid;
};

//---------------------------------------------------------------------------//
// Field tests
//---------------------------------------------------------------------------//

TEST_F(FieldTest, Constructor)
{
    // Test Field constructor
    const Field::NameType name     = "test_field";
    const FieldGridStagger stagger = FieldGridStagger::Nodal;
    const std::size_t n_component  = 1;
    const std::size_t n_ghost      = 0;
    Field field(name, grid, stagger, n_component, n_ghost);

    // Expect constructor to throw with invalid input
    EXPECT_THROW(Field("invalid_field_because_nullptr_grid", nullptr, stagger, n_component, n_ghost),
                 std::invalid_argument);
    EXPECT_THROW(Field("invalid_field_because_0_components", grid, stagger, 0, n_ghost), std::invalid_argument);

    // Test Field state after construction with the most common constructor arguments
    for (std::size_t n_component : {1, 2, 3})
    {
        for (std::size_t n_ghost : {0, 1, 2})
        {
            for (const FieldGridStagger field_stagger :
                 {FieldGridStagger::Nodal, FieldGridStagger::CellCentered, FieldGridStagger::IFace,
                  FieldGridStagger::JFace, FieldGridStagger::KFace})
            {
                Field::NameType field_name = "field_" + FieldGridStaggerToString(field_stagger) + "_ncomp_" +
                                             std::to_string(n_component) + "_nghost_" + std::to_string(n_ghost);
                Field field(field_name, grid, field_stagger, n_component, n_ghost);

                EXPECT_EQ(field.name, field_name);
                EXPECT_EQ(field.field_grid_stagger, field_stagger);

                std::shared_ptr<amrex::MultiFab> mf = field.multifab;

                EXPECT_TRUE(mf != nullptr);
                EXPECT_TRUE(mf->ok());
                EXPECT_EQ(mf->nComp(), n_component);
                EXPECT_EQ(mf->nGrow(), n_ghost);

                // Get the box that covers the entire MultiFab
                const amrex::Box& box = mf->boxArray().minimalBox();

                //  Given the field location, check the amrex indexing in each direction and the box size is correct
                switch (field.field_grid_stagger)
                {
                    case FieldGridStagger::Nodal:
                        EXPECT_TRUE(mf->is_nodal(0));
                        EXPECT_TRUE(mf->is_nodal(1));
                        EXPECT_TRUE(mf->is_nodal(2));
                        EXPECT_EQ(box.length(), amrex::IntVect(grid->NNodeI(), grid->NNodeJ(), grid->NNodeK()));
                        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
                        EXPECT_EQ(box.bigEnd(),
                                  amrex::IntVect(grid->NNodeI() - 1, grid->NNodeJ() - 1, grid->NNodeK() - 1));
                        break;
                    case FieldGridStagger::CellCentered:
                        EXPECT_FALSE(mf->is_nodal(0));
                        EXPECT_FALSE(mf->is_nodal(1));
                        EXPECT_FALSE(mf->is_nodal(2));
                        EXPECT_EQ(box.length(), amrex::IntVect(grid->NCellI(), grid->NCellJ(), grid->NCellK()));
                        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
                        EXPECT_EQ(box.bigEnd(),
                                  amrex::IntVect(grid->NCellI() - 1, grid->NCellJ() - 1, grid->NCellK() - 1));
                        break;
                    case FieldGridStagger::IFace:
                        EXPECT_TRUE(mf->is_nodal(0));
                        EXPECT_FALSE(mf->is_nodal(1));
                        EXPECT_FALSE(mf->is_nodal(2));
                        EXPECT_EQ(box.length(), amrex::IntVect(grid->NNodeI(), grid->NCellJ(), grid->NCellK()));
                        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
                        EXPECT_EQ(box.bigEnd(),
                                  amrex::IntVect(grid->NNodeI() - 1, grid->NCellJ() - 1, grid->NCellK() - 1));
                        break;
                    case FieldGridStagger::JFace:
                        EXPECT_FALSE(mf->is_nodal(0));
                        EXPECT_TRUE(mf->is_nodal(1));
                        EXPECT_FALSE(mf->is_nodal(2));
                        EXPECT_EQ(box.length(), amrex::IntVect(grid->NCellI(), grid->NNodeJ(), grid->NCellK()));
                        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
                        EXPECT_EQ(box.bigEnd(),
                                  amrex::IntVect(grid->NCellI() - 1, grid->NNodeJ() - 1, grid->NCellK() - 1));
                        break;
                    case FieldGridStagger::KFace:
                        EXPECT_FALSE(mf->is_nodal(0));
                        EXPECT_FALSE(mf->is_nodal(1));
                        EXPECT_TRUE(mf->is_nodal(2));
                        EXPECT_EQ(box.length(), amrex::IntVect(grid->NCellI(), grid->NCellJ(), grid->NNodeK()));
                        EXPECT_EQ(box.smallEnd(), amrex::IntVect(0, 0, 0));
                        EXPECT_EQ(box.bigEnd(),
                                  amrex::IntVect(grid->NCellI() - 1, grid->NCellJ() - 1, grid->NNodeK() - 1));
                        break;
                    default:
                        throw std::invalid_argument("FieldTest Constructor:: Invalid FieldGridStagger specified.");
                }
            }
        }
    }
}

TEST_F(FieldTest, StaggerChecks)
{
    std::size_t n_component = 1;
    std::size_t n_ghost     = 0;

    // The field location checks should report grid location correctly for all grid staggers
    {
        Field::NameType name     = "nodal_field";
        FieldGridStagger stagger = FieldGridStagger::Nodal;
        Field field(name, grid, stagger, n_component, n_ghost);

        EXPECT_TRUE(field.IsNodal());
        EXPECT_FALSE(field.IsCellCentered());
        EXPECT_FALSE(field.IsIFaceCentered());
        EXPECT_FALSE(field.IsJFaceCentered());
        EXPECT_FALSE(field.IsKFaceCentered());
    }

    {
        Field::NameType name     = "cell_centered_field";
        FieldGridStagger stagger = FieldGridStagger::CellCentered;
        Field field(name, grid, stagger, n_component, n_ghost);

        EXPECT_FALSE(field.IsNodal());
        EXPECT_TRUE(field.IsCellCentered());
        EXPECT_FALSE(field.IsIFaceCentered());
        EXPECT_FALSE(field.IsJFaceCentered());
        EXPECT_FALSE(field.IsKFaceCentered());
    }

    {
        Field::NameType name     = "i_face_centered_field";
        FieldGridStagger stagger = FieldGridStagger::IFace;
        Field field(name, grid, stagger, n_component, n_ghost);

        EXPECT_FALSE(field.IsNodal());
        EXPECT_FALSE(field.IsCellCentered());
        EXPECT_TRUE(field.IsIFaceCentered());
        EXPECT_FALSE(field.IsJFaceCentered());
        EXPECT_FALSE(field.IsKFaceCentered());
    }

    {
        Field::NameType name     = "j_face_centered_field";
        FieldGridStagger stagger = FieldGridStagger::JFace;
        Field field(name, grid, stagger, n_component, n_ghost);

        EXPECT_FALSE(field.IsNodal());
        EXPECT_FALSE(field.IsCellCentered());
        EXPECT_FALSE(field.IsIFaceCentered());
        EXPECT_TRUE(field.IsJFaceCentered());
        EXPECT_FALSE(field.IsKFaceCentered());
    }

    {
        Field::NameType name     = "k_face_centered_field";
        FieldGridStagger stagger = FieldGridStagger::KFace;
        Field field(name, grid, stagger, n_component, n_ghost);

        EXPECT_FALSE(field.IsNodal());
        EXPECT_FALSE(field.IsCellCentered());
        EXPECT_FALSE(field.IsIFaceCentered());
        EXPECT_FALSE(field.IsJFaceCentered());
        EXPECT_TRUE(field.IsKFaceCentered());
    }
}

TEST_F(FieldTest, GetGridPoint)
{
    // Helper function to convert FieldGridStagger to the upper loop bounds in each direction for the grid based on the
    // stagger
    auto GridSizeHelper =
        [this](FieldGridStagger field_grid_stagger) -> std::tuple<std::size_t, std::size_t, std::size_t>
    {
        switch (field_grid_stagger)
        {
            case FieldGridStagger::Nodal:
                return std::make_tuple(this->grid->NNodeI(), this->grid->NNodeJ(), this->grid->NNodeK());
            case FieldGridStagger::CellCentered:
                return std::make_tuple(this->grid->NCellI(), this->grid->NCellJ(), this->grid->NCellK());
            case FieldGridStagger::IFace:
                return std::make_tuple(this->grid->NNodeI(), this->grid->NCellJ(), this->grid->NCellK());
            case FieldGridStagger::JFace:
                return std::make_tuple(this->grid->NCellI(), this->grid->NNodeJ(), this->grid->NCellK());
            case FieldGridStagger::KFace:
                return std::make_tuple(this->grid->NCellI(), this->grid->NCellJ(), this->grid->NNodeK());
            default:
                throw std::invalid_argument("GridUpperLoopBoundsHelper invalid FieldGridStagger specified.");
        }
    };

    // Helper function to convert FieldGridStagger to the the correct grid location function
    auto GridLocationHelper = [this](FieldGridStagger field_grid_stagger, std::size_t i, std::size_t j,
                                     std::size_t k) -> Grid::Point
    {
        switch (field_grid_stagger)
        {
            case FieldGridStagger::Nodal:
                return this->grid->Node(i, j, k);
            case FieldGridStagger::CellCentered:
                return this->grid->CellCenter(i, j, k);
            case FieldGridStagger::IFace:
                return this->grid->IFace(i, j, k);
            case FieldGridStagger::JFace:
                return this->grid->JFace(i, j, k);
            case FieldGridStagger::KFace:
                return this->grid->KFace(i, j, k);
            default:
                throw std::invalid_argument("GridLocationHelper invalid FieldGridStagger specified.");
        }
    };

    // Use the same n_component and n_ghost for all the fields in this test. Should not really matter for this test.
    std::size_t n_component = 1;
    std::size_t n_ghost     = 0;

    for (const FieldGridStagger field_grid_stagger :
         {FieldGridStagger::Nodal, FieldGridStagger::CellCentered, FieldGridStagger::IFace, FieldGridStagger::JFace,
          FieldGridStagger::KFace})
    {
        Field::NameType field_name = "field_at_" + FieldGridStaggerToString(field_grid_stagger);
        Field field(field_name, grid, field_grid_stagger, n_component, n_ghost);

        auto [i_size, j_size, k_size] = GridSizeHelper(field_grid_stagger);

        // Loop over grid, for this stagger, and and compare with the location of each grid point with the location from
        // field.GetGridPoint. They should match.
        for (std::size_t i = 0; i < i_size; ++i)
        {
            for (std::size_t j = 0; j < j_size; ++j)
            {
                for (std::size_t k = 0; k < k_size; ++k)
                {
                    Grid::Point grid_location  = GridLocationHelper(field_grid_stagger, i, j, k);
                    Grid::Point field_location = field.GetGridPoint(i, j, k);
                    EXPECT_EQ(grid_location, field_location)
                        << "Field location does not match expected location for field stagger "
                        << FieldGridStaggerToString(field_grid_stagger) << " at indices (" << i << "," << j << "," << k
                        << ")";
                }
            }
        }

        // Loop over the multi-fab associated with the field, find the location of the field and compare with the
        // corresponding location in the grid. They should match. Basically checking the same thing as the previous loop
        // but this one is using the amrex indexing accessed thought the underlying multifab. This could also be run in
        // parallel or on a GPU. I could see users wanting to loop over the field or the multifab directly and get the
        // location of the field at those indices. So testing both ways here.
        for (amrex::MFIter mfi(*field.multifab); mfi.isValid(); ++mfi)
        {
            amrex::ParallelFor(mfi.validbox(),
                               [=, this] AMREX_GPU_DEVICE(int i, int j, int k)
                               {
                                   Grid::Point grid_location  = GridLocationHelper(field_grid_stagger, i, j, k);
                                   Grid::Point field_location = field.GetGridPoint(i, j, k);
                                   EXPECT_EQ(grid_location, field_location);
                               });
        }
    }
}

//TEST_F(FieldTest, Initialize)
//{
//    Field::NameType name     = "test_field";
//    FieldGridStagger stagger = FieldGridStagger::Nodal;
//    std::size_t n_component  = 2;
//    std::size_t n_ghost      = 0;
//    Field field(name, grid, stagger, n_component, n_ghost);
//
//    // Define an initializer function that initializes a vector field with two components
//    auto initializer_function = [](double x, double y, double z) -> std::vector<Field::ValueType>
//    {
//        return {x + y + z, x * y * z};
//    };
//
//    field.Initialize(initializer_function);
//
//    // Verify that the field data has been initialized correctly
//    std::shared_ptr<amrex::MultiFab> multifab = field.multifab;
//    for (amrex::MFIter mfi(*multifab); mfi.isValid(); ++mfi)
//    {
//        const amrex::Array4<amrex::Real>& array = multifab->array(mfi);
//        amrex::ParallelFor(mfi.validbox(),
//                           [=, this] AMREX_GPU_DEVICE(int i, int j, int k)
//                           {
//                               Grid::Point grid_point = field.GetGridPoint(i, j, k);
//                               EXPECT_EQ(array(i, j, k, 0), grid_point.x + grid_point.y + grid_point.z);
//                               EXPECT_EQ(array(i, j, k, 1), grid_point.x * grid_point.y * grid_point.z);
//                           });
//    }
//}

TEST_F(FieldTest, WriteHDF5)
{
    Field::NameType name     = "test_field";
    FieldGridStagger stagger = FieldGridStagger::Nodal;
    std::size_t n_component  = 1;
    std::size_t n_ghost      = 0;
    Field field(name, grid, stagger, n_component, n_ghost);

    // Test the version that takes a file_id of an already opened HDF5 file
    {
        const std::string filename = "Test_Output_Field_WriteHDF5_via_file_id.h5";
        const hid_t file_id        = H5Fcreate(filename.c_str(), H5F_ACC_TRUNC, H5P_DEFAULT, H5P_DEFAULT);
        field.WriteHDF5(file_id);
        H5Fclose(file_id);
    }

    // Test the version that takes a filename. This will override the previous file.
    {
        const std::string filename = "Test_Output_Field_WriteHDF5_via_filename.h5";
        field.WriteHDF5(filename);
    }
}